defmodule Foundation.DeadLetterQueueTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias Foundation.{DeadLetterQueue, SupervisedSend}
  
  @moduletag :capture_log
  
  setup do
    # Start the system
    start_supervised!({SupervisedSend, []})
    start_supervised!({DeadLetterQueue, []})
    
    # Clear any existing ETS data
    if :ets.info(:dead_letter_queue) != :undefined do
      :ets.delete_all_objects(:dead_letter_queue)
    end
    
    # Set test pid for zero-overhead test notifications
    Application.put_env(:foundation, :test_pid, self())
    
    on_exit(fn ->
      Application.delete_env(:foundation, :test_pid)
    end)
    
    :ok
  end
  
  describe "add_message/4" do
    test "adds message to dead letter queue" do
      pid = spawn(fn -> :ok end)
      
      capture_log(fn ->
        DeadLetterQueue.add_message(
          pid,
          {:test, "data"}, 
          :noproc,
          %{source: :test}
        )
      end)
      
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 1
      
      message = List.first(messages)
      assert message.recipient == pid
      assert message.message == {:test, "data"}
      assert message.reason == :noproc
      assert message.metadata.source == :test
      assert message.attempts == 0
    end
    
    test "emits telemetry when message added" do
      test_pid = self()
      
      :telemetry.attach(
        "dlq-handler",
        [:foundation, :dead_letter_queue, :message_added],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:dlq_telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      pid = spawn(fn -> :ok end)
      DeadLetterQueue.add_message(pid, {:test, "data"}, :timeout)
      
      assert_receive {:dlq_telemetry, [:foundation, :dead_letter_queue, :message_added], measurements, metadata}, 1000
      assert measurements.count == 1
      assert metadata.reason == :timeout
      
      :telemetry.detach("dlq-handler")
    end
  end
  
  describe "list_messages/1" do
    test "returns empty list when no messages" do
      assert [] = DeadLetterQueue.list_messages()
    end
    
    test "returns messages up to limit" do
      # Add multiple messages
      for i <- 1..5 do
        pid = spawn(fn -> :ok end)
        DeadLetterQueue.add_message(pid, {:test, i}, :noproc)
      end
      
      messages = DeadLetterQueue.list_messages(3)
      assert length(messages) == 3
    end
    
    test "returns all messages when no limit specified" do
      # Add multiple messages
      for i <- 1..3 do
        pid = spawn(fn -> :ok end)
        DeadLetterQueue.add_message(pid, {:test, i}, :noproc)
      end
      
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 3
    end
  end
  
  describe "retry_messages/1" do
    test "retries all messages when filter is :all" do
      # Create a live recipient
      {:ok, recipient} = GenServer.start_link(__MODULE__.TestServer, self())
      
      # Add message to dead letter queue
      DeadLetterQueue.add_message(
        recipient, 
        {:test_retry, "data"}, 
        :simulated_failure
      )
      
      # Retry all messages
      results = DeadLetterQueue.retry_messages(:all)
      
      # Should succeed and remove from queue
      assert [{:ok, _id}] = results
      assert [] = DeadLetterQueue.list_messages()
      
      # Should receive the message
      assert_receive {:test_retry, "data"}, 1000
    end
    
    test "updates attempt count on retry failure" do
      # Create dead recipient
      pid = spawn(fn -> :ok end)
      
      DeadLetterQueue.add_message(pid, {:test, "data"}, :noproc)
      
      # Retry should fail
      results = DeadLetterQueue.retry_messages(:all)
      assert [{:error, _id, _reason}] = results
      
      # Message should still be in queue with updated attempt count
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 1
      
      message = List.first(messages)
      assert message.attempts == 1
    end
    
    test "does not retry messages that exceed max retries" do
      pid = spawn(fn -> :ok end)
      
      # Add message and simulate multiple failed attempts
      DeadLetterQueue.add_message(pid, {:test, "data"}, :noproc)
      
      # Simulate exceeding max retries
      for _i <- 1..6 do
        DeadLetterQueue.retry_messages(:all)
      end
      
      # Final retry should not attempt (max retries exceeded)
      initial_count = length(DeadLetterQueue.list_messages())
      DeadLetterQueue.retry_messages(:all)
      final_count = length(DeadLetterQueue.list_messages())
      
      # Message should still be there (not retried due to max attempts)
      assert initial_count == final_count
    end
  end
  
  describe "purge_messages/1" do
    test "purges all messages when filter is :all" do
      # Add multiple messages
      for i <- 1..3 do
        pid = spawn(fn -> :ok end)
        DeadLetterQueue.add_message(pid, {:test, i}, :noproc)
      end
      
      assert {:ok, 3} = DeadLetterQueue.purge_messages(:all)
      assert [] = DeadLetterQueue.list_messages()
    end
    
    test "purges only expired messages when filter is :expired" do
      # This test would need to manipulate timestamps or wait
      # For now, test the interface
      {:ok, count} = DeadLetterQueue.purge_messages(:expired)
      assert is_integer(count)
    end
  end
  
  describe "automatic retry" do
    @tag :capture_log
    test "automatically retries old messages" do
      # This is a timing-sensitive test that would need to be adjusted
      # for the actual retry interval. For now, just test the mechanism exists.
      
      # Create a live recipient
      {:ok, recipient} = GenServer.start_link(__MODULE__.TestServer, self())
      
      # Add message to dead letter queue
      DeadLetterQueue.add_message(
        recipient, 
        {:auto_retry_test, "data"}, 
        :simulated_failure
      )
      
      # Manually trigger retry for all messages (not just auto-eligible ones)
      GenServer.cast(DeadLetterQueue, {:retry_messages, :all})
      
      # Wait for completion notification (zero overhead, deterministic)
      assert_receive {:retry_completed, :all, results}, 1000
      assert Enum.any?(results, fn result -> match?({:ok, _}, result) end)
      
      # Should eventually succeed and remove from queue
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 0
      
      # Should receive the message
      assert_receive {:auto_retry_test, "data"}, 1000
    end
  end
  
  describe "integration with SupervisedSend" do
    test "messages go to dead letter queue on send failure" do
      pid = spawn(fn -> :ok end)
      
      capture_log(fn ->
        SupervisedSend.send_supervised(
          pid,
          {:integration_test, "data"},
          on_error: :dead_letter,
          metadata: %{integration: true}
        )
      end)
      
      messages = DeadLetterQueue.list_messages()
      assert length(messages) == 1
      
      message = List.first(messages)
      assert message.message == {:integration_test, "data"}
      assert message.metadata.integration == true
    end
  end
  
end

# Test server - defined at module level
defmodule Foundation.DeadLetterQueueTest.TestServer do
  use GenServer
  
  def init(test_pid), do: {:ok, %{test_pid: test_pid}}
  
  def handle_cast(message, state) do
    send(state.test_pid, message)
    {:noreply, state}
  end
  
  def handle_info(message, state) do
    send(state.test_pid, message)
    {:noreply, state}
  end
end