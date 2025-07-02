defmodule Foundation.SupervisedSendTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias Foundation.{SupervisedSend, DeadLetterQueue}
  
  @moduletag :capture_log
  
  setup do
    # Start the supervised send system
    start_supervised!({SupervisedSend, []})
    start_supervised!({DeadLetterQueue, []})
    
    # Clear any existing ETS data
    if :ets.info(:supervised_send_tracking) != :undefined do
      :ets.delete_all_objects(:supervised_send_tracking)
    end
    
    if :ets.info(:dead_letter_queue) != :undefined do
      :ets.delete_all_objects(:dead_letter_queue)
    end
    
    :ok
  end
  
  describe "send_supervised/3" do
    test "successfully sends message to live process" do
      {:ok, recipient} = GenServer.start_link(__MODULE__.EchoServer, self())
      
      assert :ok = SupervisedSend.send_supervised(recipient, {:echo, "hello"})
      
      assert_receive {:echoed, "hello"}, 1000
    end
    
    test "returns error for dead process" do
      {:ok, pid} = GenServer.start_link(__MODULE__.EchoServer, self())
      ref = Process.monitor(pid)
      GenServer.stop(pid)
      
      # Wait for confirmed termination
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
      
      assert {:error, :noproc} = 
        SupervisedSend.send_supervised(pid, {:echo, "hello"})
    end
    
    test "returns error for named process that doesn't exist" do
      assert {:error, :noproc} = 
        SupervisedSend.send_supervised(:non_existent_process, {:echo, "hello"})
    end
    
    test "retries on dead process" do
      # Test retry on a process that's already dead
      pid = spawn(fn -> :ok end)  # Dies immediately
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
      
      result = SupervisedSend.send_supervised(
        pid, 
        {:process, "data"},
        retries: 2,
        backoff: 10
      )
      
      # Should fail - can't retry to dead process
      assert {:error, :noproc} = result
    end
    
    test "handles slow processing correctly" do
      {:ok, slow} = GenServer.start_link(__MODULE__.SlowServer, %{delay: 200})
      
      # SupervisedSend doesn't timeout on slow processing - it just ensures delivery
      result = SupervisedSend.send_supervised(
        slow,
        {:slow_process, "data"},
        timeout: 500
      )
      
      # Should succeed - the message is delivered even if processing is slow
      assert :ok = result
    end
    
    test "sends to dead letter queue on error" do
      {:ok, pid} = GenServer.start_link(__MODULE__.EchoServer, self())
      GenServer.stop(pid)
      
      # This should fail and go to dead letter queue
      capture_log(fn ->
        SupervisedSend.send_supervised(
          pid, 
          {:important, "data"},
          on_error: :dead_letter,
          metadata: %{job_id: "test_123"}
        )
      end)
      
      # Check dead letter queue
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 1
      
      message = List.first(messages)
      assert message.message == {:important, "data"}
      assert message.metadata.job_id == "test_123"
    end
    
    test "logs errors when configured" do
      {:ok, pid} = GenServer.start_link(__MODULE__.EchoServer, self())
      GenServer.stop(pid)
      
      log = capture_log(fn ->
        SupervisedSend.send_supervised(
          pid, 
          {:test, "data"},
          on_error: :log
        )
      end)
      
      assert log =~ "Supervised send failed"
    end
    
    test "raises on error when configured" do
      {:ok, pid} = GenServer.start_link(__MODULE__.EchoServer, self())
      GenServer.stop(pid)
      
      assert_raise RuntimeError, ~r/Supervised send failed/, fn ->
        SupervisedSend.send_supervised(
          pid, 
          {:test, "data"},
          on_error: :raise
        )
      end
    end
  end
  
  describe "broadcast_supervised/3" do
    test "best effort strategy returns all results" do
      recipients = create_test_recipients(3)
      
      assert {:ok, results} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :best_effort
      )
      
      assert length(results) == 3
      assert Enum.all?(results, fn {_id, result, _meta} -> result == :ok end)
    end
    
    test "best effort strategy handles partial failures" do
      recipients = create_test_recipients(3)
      
      # Kill one recipient
      [{_id, first_pid, _meta} | _rest] = recipients
      GenServer.stop(first_pid)
      
      assert {:ok, results} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :best_effort,
        timeout: 1000
      )
      
      # Should have all results, some failed
      assert length(results) == 3
      failed_count = Enum.count(results, fn {_id, result, _meta} -> 
        result != :ok 
      end)
      assert failed_count == 1
    end
    
    test "all or nothing strategy fails if any recipient fails" do
      recipients = create_test_recipients(3)
      
      # Kill one recipient
      [{_id, first_pid, _meta} | _rest] = recipients
      GenServer.stop(first_pid)
      
      assert {:error, :noproc} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :all_or_nothing
      )
    end
    
    test "all or nothing strategy succeeds if all recipients are alive" do
      recipients = create_test_recipients(3)
      
      assert {:ok, results} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :all_or_nothing
      )
      
      assert length(results) == 3
      assert Enum.all?(results, fn {_id, result} -> result == :ok end)
    end
    
    test "at least one strategy succeeds if one recipient succeeds" do
      recipients = create_test_recipients(3)
      
      # Kill two recipients, leave one alive
      [{_id1, pid1, _meta1}, {_id2, pid2, _meta2} | _rest] = recipients
      GenServer.stop(pid1)
      GenServer.stop(pid2)
      
      assert {:ok, result_list} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :at_least_one
      )
      
      # Should have results from all attempts
      assert length(result_list) == 3
      
      # At least one should have succeeded
      success_count = Enum.count(result_list, fn {_id, result, _meta} -> 
        result == :ok 
      end)
      assert success_count >= 1
    end
    
    test "at least one strategy fails if all recipients fail" do
      recipients = create_test_recipients(3)
      
      # Kill all recipients
      Enum.each(recipients, fn {_id, pid, _meta} ->
        GenServer.stop(pid)
      end)
      
      assert {:error, :all_failed} = SupervisedSend.broadcast_supervised(
        recipients,
        {:broadcast, "test"},
        strategy: :at_least_one
      )
    end
  end
  
  describe "send_to_self/1" do
    test "always succeeds" do
      assert :ok = SupervisedSend.send_to_self({:self_message, "test"})
      assert_receive {:self_message, "test"}, 100
    end
  end
  
  describe "telemetry events" do
    test "emits telemetry on successful send" do
      {:ok, recipient} = GenServer.start_link(__MODULE__.EchoServer, self())
      
      # Listen for telemetry span events (start, stop, exception)
      :telemetry.attach_many(
        "test-handler",
        [
          [:foundation, :supervised_send, :send, :start],
          [:foundation, :supervised_send, :send, :stop],
          [:foundation, :supervised_send, :send, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      SupervisedSend.send_supervised(recipient, {:echo, "test"})
      
      # Should receive start event
      assert_receive {:telemetry, [:foundation, :supervised_send, :send, :start], _measurements, _metadata}, 1000
      
      # Should receive stop event
      assert_receive {:telemetry, [:foundation, :supervised_send, :send, :stop], _measurements, metadata}, 1000
      assert metadata.result == :ok
      
      :telemetry.detach("test-handler")
    end
    
    test "emits telemetry on error" do
      pid = spawn(fn -> :ok end)  # Dies immediately
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
      
      :telemetry.attach_many(
        "error-handler",
        [
          [:foundation, :supervised_send, :send, :start],
          [:foundation, :supervised_send, :send, :stop],
          [:foundation, :supervised_send, :send, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      SupervisedSend.send_supervised(pid, {:test, "data"})
      
      # Should receive start event
      assert_receive {:telemetry, [:foundation, :supervised_send, :send, :start], _measurements, _metadata}, 1000
      
      # Should receive stop event  
      assert_receive {:telemetry, [:foundation, :supervised_send, :send, :stop], _measurements, metadata}, 1000
      assert {:error, :noproc} = metadata.result
      
      :telemetry.detach("error-handler")
    end
  end
  
  # Test helpers
  
  defp create_test_recipients(count) do
    for i <- 1..count do
      {:ok, pid} = GenServer.start_link(__MODULE__.EchoServer, self())
      {i, pid, %{}}
    end
  end
end

# Test helper servers - defined at module level
defmodule Foundation.SupervisedSendTest.EchoServer do
  use GenServer
  
  def init(test_pid), do: {:ok, %{test_pid: test_pid}}
  
  def handle_cast({:echo, msg}, state) do
    send(state.test_pid, {:echoed, msg})
    {:noreply, state}
  end
  
  def handle_cast({:broadcast, msg}, state) do
    send(state.test_pid, {:broadcast_received, msg})
    {:noreply, state}
  end
  
  def handle_info({:echo, msg}, state) do
    # Handle direct send messages (from SupervisedSend)
    send(state.test_pid, {:echoed, msg})
    {:noreply, state}
  end
  
  def handle_info({:broadcast, msg}, state) do
    # Handle direct send messages (from SupervisedSend)
    send(state.test_pid, {:broadcast_received, msg})
    {:noreply, state}
  end
  
  def handle_info(_msg, state) do
    # Handle unexpected messages gracefully
    {:noreply, state}
  end
end

defmodule Foundation.SupervisedSendTest.FlakyServer do
  use GenServer
  
  def init(%{fail_count: fail_count, test_pid: test_pid}) do
    {:ok, %{fail_count: fail_count, attempts: 0, test_pid: test_pid}}
  end
  
  def handle_cast({:process, _data}, state) do
    new_attempts = state.attempts + 1
    send(state.test_pid, {:attempt, new_attempts})
    
    if new_attempts <= state.fail_count do
      {:stop, :induced_failure, %{state | attempts: new_attempts}}
    else
      {:noreply, %{state | attempts: new_attempts}}
    end
  end
  
  def handle_info({:process, _data}, state) do
    # Handle direct send messages (from SupervisedSend)
    new_attempts = state.attempts + 1
    send(state.test_pid, {:attempt, new_attempts})
    
    if new_attempts <= state.fail_count do
      {:stop, :induced_failure, %{state | attempts: new_attempts}}
    else
      {:noreply, %{state | attempts: new_attempts}}
    end
  end
end

defmodule Foundation.SupervisedSendTest.SlowServer do
  use GenServer
  
  def init(%{delay: delay}), do: {:ok, %{delay: delay}}
  
  def handle_cast({:slow_process, _data}, state) do
    Process.sleep(state.delay)
    {:noreply, state}
  end
  
  def handle_info({:slow_process, _data}, state) do
    # Handle direct send messages (from SupervisedSend)
    Process.sleep(state.delay)
    {:noreply, state}
  end
end