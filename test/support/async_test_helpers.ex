defmodule Foundation.AsyncTestHelpers do
  @moduledoc """
  Helpers for testing asynchronous operations without using Process.sleep.

  Based on the guidelines in docs20250627/042_SLEEP.md
  """

  @doc """
  Polls a function until it returns a truthy value or a timeout is reached.

  This is an acceptable replacement for `Process.sleep/1` in tests for
  complex async scenarios.
  """
  def wait_for(fun, timeout \\ 1_000, interval \\ 10) do
    start_time = System.monotonic_time(:millisecond)

    check_fun = fn check_fun ->
      case fun.() do
        result when result != nil and result != false ->
          result

        _ ->
          handle_wait_timeout(check_fun, start_time, timeout, interval)
      end
    end

    check_fun.(check_fun)
  end

  defp handle_wait_timeout(check_fun, start_time, timeout, interval) do
    if System.monotonic_time(:millisecond) - start_time > timeout do
      ExUnit.Assertions.flunk("wait_for timed out after #{timeout}ms")
    else
      Process.sleep(interval)
      check_fun.(check_fun)
    end
  end

  @doc """
  Waits for a telemetry event to be emitted.

  ## Example

      assert_telemetry_event [:my_app, :event], %{count: 1} do
        MyApp.trigger_event()
      end
  """
  defmacro assert_telemetry_event(
             event_name,
             expected_measurements \\ %{},
             expected_metadata \\ %{},
             do: block
           ) do
    quote do
      test_pid = self()
      ref = make_ref()

      handler = fn ^unquote(event_name), measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, measurements, metadata})
      end

      :telemetry.attach({__MODULE__, unquote(event_name), ref}, unquote(event_name), handler, nil)

      try do
        # Execute the block that should trigger the event
        unquote(block)

        # Wait for the event
        assert_receive {:telemetry_event, ^ref, measurements, metadata}, 1000

        # Verify measurements if provided
        for {key, expected_value} <- unquote(expected_measurements) do
          assert Map.get(measurements, key) == expected_value
        end

        # Verify metadata if provided
        for {key, expected_value} <- unquote(expected_metadata) do
          assert Map.get(metadata, key) == expected_value
        end

        {measurements, metadata}
      after
        :telemetry.detach({__MODULE__, unquote(event_name), ref})
      end
    end
  end

  @doc """
  Starts a process and waits for it to send a ready signal.

  ## Example

      {:ok, pid} = start_and_wait_ready(fn ->
        MyWorker.start_link(parent: self())
      end)
  """
  def start_and_wait_ready(start_fun, timeout \\ 5_000) do
    case start_fun.() do
      {:ok, pid} = result ->
        receive do
          {:ready, ^pid} -> result
          {atom, ^pid} when atom in [:initialized, :started, :worker_ready] -> result
        after
          timeout ->
            Process.exit(pid, :kill)
            {:error, :initialization_timeout}
        end

      error ->
        error
    end
  end

  @doc """
  Ensures a process has processed all messages in its mailbox.

  Useful for testing that a GenServer has handled all pending messages
  before making assertions about its state.
  """
  def sync_with_process(pid, timeout \\ 1_000) do
    ref = make_ref()
    GenServer.call(pid, {:sync, ref}, timeout)
    ref
  end

  @doc """
  Wait for multiple events with proper synchronization.
  Replaces Process dictionary-based event coordination.

  ## Example

      wait_for_events([
        {:agent_registered, {:agent_registered, :my_agent}},
        {:monitor_created, {:monitor_created, _pid}}
      ], timeout: 2000)
  """
  def wait_for_events(event_specs, timeout \\ 5000) do
    parent = self()
    collectors = start_event_collectors(event_specs, parent, timeout)
    
    try do
      wait_for_all_events(collectors, timeout)
    after
      cleanup_collectors(collectors)
    end
  end

  defp start_event_collectors(event_specs, parent, timeout) do
    Enum.map(event_specs, fn {name, pattern} ->
      collector_pid = spawn_link(fn ->
        receive do
          ^pattern -> send(parent, {:event_received, name})
          msg when elem(msg, 0) == elem(pattern, 0) -> 
            send(parent, {:event_received, name})
        after
          timeout -> send(parent, {:event_timeout, name})
        end
      end)
      
      {name, collector_pid}
    end)
  end

  defp wait_for_all_events([], _timeout), do: :ok
  
  defp wait_for_all_events(collectors, timeout) do
    receive do
      {:event_received, name} ->
        remaining = List.keydelete(collectors, name, 0)
        wait_for_all_events(remaining, timeout)
        
      {:event_timeout, name} ->
        {:error, {:timeout, name}}
    after
      timeout -> {:error, :global_timeout}
    end
  end

  defp cleanup_collectors(collectors) do
    Enum.each(collectors, fn {_name, pid} ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
  end

  @doc """
  Wait for a condition to be true with exponential backoff.
  More efficient than polling for async conditions.

  ## Example

      wait_until(fn ->
        Registry.lookup(MyRegistry, :my_key) != []
      end, timeout: 5000)
  """
  def wait_until(condition_fun, timeout \\ 5000) when is_function(condition_fun, 0) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_until_loop(condition_fun, end_time, 1)
  end

  defp wait_until_loop(condition_fun, end_time, backoff) do
    if condition_fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= end_time do
        {:error, :timeout}
      else
        sleep_time = min(backoff, 100)
        Process.sleep(sleep_time)
        wait_until_loop(condition_fun, end_time, min(backoff * 2, 100))
      end
    end
  end

  @doc """
  Waits for a specific message pattern.
  Replacement for Process dictionary state checking.

  ## Example

      wait_for_message({:result, _value}, timeout: 1000)
  """
  def wait_for_message(pattern, timeout \\ 5000) do
    receive do
      ^pattern = msg -> {:ok, msg}
      msg when elem(msg, 0) == elem(pattern, 0) -> {:ok, msg}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Creates an async test context that uses message passing instead of Process dictionary.
  
  ## Example

      with_async_context fn context ->
        context.send_event(:test_started)
        # Do test work
        assert_receive {:test_event, :test_started}
      end
  """
  def with_async_context(test_fun) when is_function(test_fun, 1) do
    parent = self()
    
    context = %{
      send_event: fn event -> send(parent, {:test_event, event}) end,
      store_value: fn key, value -> send(parent, {:store, key, value}) end,
      notify_completion: fn result -> send(parent, {:test_complete, result}) end
    }
    
    test_fun.(context)
  end

  @doc """
  Monitors a process and returns a reference for cleanup.
  Replaces Process dictionary monitoring storage.

  ## Example

      monitor_ref = monitor_process(pid)
      # ... test work ...
      cleanup_monitor(monitor_ref)
  """
  def monitor_process(pid) when is_pid(pid) do
    Process.monitor(pid)
  end

  def cleanup_monitor(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
  end

  @doc """
  Sets up temporary message-based storage for tests.
  Replaces Process dictionary caching patterns.

  ## Example

      {:ok, storage} = setup_test_storage()
      store_test_value(storage, :key, :value)
      assert get_test_value(storage, :key) == :value
      cleanup_test_storage(storage)
  """
  def setup_test_storage do
    storage_pid = spawn_link(fn -> test_storage_loop(%{}) end)
    {:ok, storage_pid}
  end

  def store_test_value(storage_pid, key, value) do
    send(storage_pid, {:store, key, value, self()})
    receive do
      {:stored, ^key} -> :ok
    after
      1000 -> {:error, :timeout}
    end
  end

  def get_test_value(storage_pid, key) do
    send(storage_pid, {:get, key, self()})
    receive do
      {:value, ^key, value} -> value
      {:not_found, ^key} -> nil
    after
      1000 -> {:error, :timeout}
    end
  end

  def cleanup_test_storage(storage_pid) do
    if Process.alive?(storage_pid) do
      Process.exit(storage_pid, :normal)
    end
  end

  defp test_storage_loop(state) do
    receive do
      {:store, key, value, from} ->
        new_state = Map.put(state, key, value)
        send(from, {:stored, key})
        test_storage_loop(new_state)
        
      {:get, key, from} ->
        case Map.get(state, key) do
          nil -> send(from, {:not_found, key})
          value -> send(from, {:value, key, value})
        end
        test_storage_loop(state)
    end
  end

  @doc """
  Creates a test agent for holding state instead of Process dictionary.
  More OTP-compliant than Process dictionary.

  ## Example

      {:ok, agent} = start_test_agent(%{initial: :state})
      update_test_agent(agent, fn state -> Map.put(state, :key, :value) end)
      assert get_test_agent_state(agent).key == :value
      stop_test_agent(agent)
  """
  def start_test_agent(initial_state \\ %{}) do
    Agent.start_link(fn -> initial_state end)
  end

  def get_test_agent_state(agent) do
    Agent.get(agent, & &1)
  end

  def update_test_agent(agent, update_fun) do
    Agent.update(agent, update_fun)
  end

  def stop_test_agent(agent) do
    Agent.stop(agent)
  end
end
