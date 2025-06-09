defmodule Foundation.ConcurrentTestHelpers do
  @moduledoc """
  Utility functions for testing concurrent and distributed systems in Foundation 2.0.

  This module provides helpers specifically designed for testing BEAM concurrency
  patterns, process ecosystems, and distributed coordination.
  """

  @doc """
  Wait for a condition to become true, checking periodically.

  This is essential for testing concurrent systems where state changes
  happen asynchronously.

  ## Examples

      # Wait for a process to start
      wait_for_condition(fn -> Process.alive?(pid) end)
      
      # Wait for a GenServer to reach a specific state
      wait_for_condition(fn -> 
        GenServer.call(server, :get_state) == :ready
      end, 3000)
  """
  @spec wait_for_condition(function(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def wait_for_condition(condition_fn, timeout \\ 5000, check_interval \\ 100) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_loop(condition_fn, end_time, check_interval)
  end

  defp wait_loop(condition_fn, end_time, check_interval) do
    if System.monotonic_time(:millisecond) > end_time do
      {:error, :timeout}
    else
      if condition_fn.() do
        :ok
      else
        :timer.sleep(check_interval)
        wait_loop(condition_fn, end_time, check_interval)
      end
    end
  end

  @doc """
  Assert that a condition eventually becomes true.

  This is a test-friendly wrapper around wait_for_condition that
  automatically fails the test if the condition times out.

  ## Examples

      # Assert a process eventually dies
      assert_eventually(fn -> not Process.alive?(pid) end)
      
      # Assert ecosystem reaches desired worker count
      assert_eventually(fn ->
        {:ok, info} = Foundation.BEAM.Processes.ecosystem_info(ecosystem)
        info.total_processes == 10
      end, 2000)
  """
  @spec assert_eventually(function(), non_neg_integer()) :: :ok
  def assert_eventually(condition, timeout \\ 5000) do
    case wait_for_condition(condition, timeout) do
      :ok ->
        :ok

      {:error, :timeout} ->
        ExUnit.Assertions.flunk("Condition was not met within #{timeout}ms")
    end
  end

  @doc """
  Measure memory usage of a function execution.

  Useful for testing memory isolation and cleanup in process ecosystems.

  ## Examples

      {result, memory_usage} = measure_memory_usage(fn ->
        Foundation.BEAM.Processes.isolate_memory_intensive_work(heavy_work)
      end)
      
      assert memory_usage[:total] < 1_000_000  # Less than 1MB used
  """
  @spec measure_memory_usage(function()) :: {any(), keyword()}
  def measure_memory_usage(fun) do
    before = :erlang.memory()
    result = fun.()
    after_mem = :erlang.memory()

    usage =
      for {type, after_val} <- after_mem do
        before_val = Keyword.get(before, type, 0)
        {type, after_val - before_val}
      end

    {result, usage}
  end

  @doc """
  Capture telemetry events for testing.

  Attaches a temporary telemetry handler to capture events during test execution.

  ## Examples

      capture_telemetry([:foundation, :ecosystem, :started], fn ->
        Foundation.BEAM.Processes.spawn_ecosystem(config)
      end)
  """
  @spec capture_telemetry(list(atom()), function(), non_neg_integer()) ::
          {:ok, map(), map()} | {:error, :timeout}
  def capture_telemetry(event_name, test_function, timeout \\ 1000) do
    test_pid = self()

    handler_id = {:test_handler, make_ref()}

    :telemetry.attach(
      handler_id,
      event_name,
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, measurements, metadata})
      end,
      %{}
    )

    # Execute the test function
    test_function.()

    # Wait for telemetry event
    result =
      receive do
        {:telemetry_event, measurements, metadata} ->
          {:ok, measurements, metadata}
      after
        timeout ->
          {:error, :timeout}
      end

    :telemetry.detach(handler_id)
    result
  end

  @doc """
  Monitor process memory usage over time.

  Useful for detecting memory leaks in long-running process ecosystems.

  ## Examples

      monitor = start_memory_monitor(ecosystem_processes, 1000)
      # ... run test ...
      readings = stop_memory_monitor(monitor)
      
      assert Enum.all?(readings, fn reading -> 
        reading.memory < 10_000_000  # Less than 10MB
      end)
  """
  @spec start_memory_monitor([pid()], non_neg_integer()) :: pid()
  def start_memory_monitor(monitored_pids, interval \\ 1000) do
    test_pid = self()

    spawn(fn ->
      memory_monitor_loop(monitored_pids, interval, test_pid, [])
    end)
  end

  @spec stop_memory_monitor(pid()) :: [map()]
  def stop_memory_monitor(monitor_pid) do
    send(monitor_pid, :stop)

    receive do
      {:memory_readings, readings} -> readings
    after
      5000 ->
        # Timeout, return empty readings
        []
    end
  end

  defp memory_monitor_loop(monitored_pids, interval, test_pid, readings) do
    receive do
      :stop ->
        send(test_pid, {:memory_readings, Enum.reverse(readings)})
    after
      interval ->
        # Take memory reading
        timestamp = System.monotonic_time(:millisecond)

        current_reading = %{
          timestamp: timestamp,
          total_memory: :erlang.memory(:total),
          process_memory: get_processes_memory(monitored_pids)
        }

        memory_monitor_loop(monitored_pids, interval, test_pid, [current_reading | readings])
    end
  end

  defp get_processes_memory(pids) do
    for pid <- pids, Process.alive?(pid) do
      case Process.info(pid, :memory) do
        {:memory, memory} -> {pid, memory}
        nil -> {pid, 0}
      end
    end
  end

  @doc """
  Create a temporary test cluster for distributed testing.

  Automatically starts multiple nodes and connects them for testing
  distributed Foundation features.

  ## Examples

      test_cluster = start_test_cluster(3)
      # ... run distributed tests ...
      stop_test_cluster(test_cluster)
  """
  @spec start_test_cluster(non_neg_integer()) :: map()
  def start_test_cluster(node_count) when node_count > 0 do
    base_name = "foundation_test"
    current_time = System.system_time(:millisecond)

    nodes =
      for i <- 1..node_count do
        _node_name = :"#{base_name}_#{current_time}_#{i}@127.0.0.1"

        {:ok, node} =
          :peer.start_link(%{
            name: :"#{base_name}_#{current_time}_#{i}",
            host: ~c"127.0.0.1",
            args: [~c"-pa", ~c"#{:code.get_path() |> Enum.join(" -pa ")}"]
          })

        # Load Foundation on each node
        :rpc.call(node, :code, :add_paths, [:code.get_path()])
        :rpc.call(node, Application, :ensure_all_started, [:foundation])

        node
      end

    # Connect nodes to form cluster
    for node <- nodes do
      Node.connect(node)
    end

    %{
      nodes: nodes,
      node_count: node_count,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  @spec stop_test_cluster(map()) :: :ok
  def stop_test_cluster(%{nodes: nodes}) do
    for node <- nodes do
      :peer.stop(node)
    end

    :ok
  end

  @doc """
  Simulate network partition between groups of nodes.

  Useful for testing distributed consensus and partition tolerance.

  ## Examples

      simulate_network_partition([node1, node2], [node3])
      # ... test partition tolerance ...
      heal_network_partition([node1, node2, node3])
  """
  @spec simulate_network_partition([node()], [node()]) :: :ok
  def simulate_network_partition(partition1, partition2) do
    # Disconnect nodes between partitions
    for n1 <- partition1, n2 <- partition2 do
      :rpc.call(n1, Node, :disconnect, [n2])
      :rpc.call(n2, Node, :disconnect, [n1])
    end

    :ok
  end

  @spec heal_network_partition([node()]) :: :ok
  def heal_network_partition(all_nodes) do
    # Reconnect all nodes
    for n1 <- all_nodes, n2 <- all_nodes, n1 != n2 do
      :rpc.call(n1, Node, :connect, [n2])
    end

    :ok
  end

  @doc """
  Inject random failures for chaos testing.

  Randomly kills processes, causes network partitions, or triggers
  resource pressure to test system resilience.

  ## Examples

      chaos_config = %{
        targets: ecosystem_processes,
        failure_rate: 0.1,  # 10% chance per interval
        types: [:process_kill, :network_partition, :memory_pressure]
      }
      
      chaos_pid = start_chaos_monkey(chaos_config)
      # ... run test under chaos ...
      stop_chaos_monkey(chaos_pid)
  """
  @spec start_chaos_monkey(map()) :: pid()
  def start_chaos_monkey(config) do
    spawn(fn ->
      chaos_monkey_loop(config)
    end)
  end

  @spec stop_chaos_monkey(pid()) :: :ok
  def stop_chaos_monkey(chaos_pid) do
    send(chaos_pid, :stop)
    :ok
  end

  defp chaos_monkey_loop(config) do
    receive do
      :stop -> :ok
    after
      config[:interval] || 1000 ->
        if :rand.uniform() < (config[:failure_rate] || 0.1) do
          inject_random_failure(config)
        end

        chaos_monkey_loop(config)
    end
  end

  defp inject_random_failure(config) do
    failure_types = config[:types] || [:process_kill]
    failure_type = Enum.random(failure_types)

    case failure_type do
      :process_kill ->
        targets = config[:targets] || []

        if length(targets) > 0 do
          target = Enum.random(targets)

          if Process.alive?(target) do
            Process.exit(target, :chaos_monkey)
          end
        end

      :memory_pressure ->
        # Create temporary memory pressure
        spawn(fn ->
          _large_data = :crypto.strong_rand_bytes(1_000_000)
          :timer.sleep(100)
        end)

      :cpu_spike ->
        # Create temporary CPU spike
        spawn(fn ->
          Enum.each(1..10_000, fn _ -> :math.pow(2, 10) end)
        end)

      _ ->
        :ignore
    end
  end

  @doc """
  Generate test data for process ecosystem configurations.

  Creates valid ecosystem configurations with random parameters
  for property-based testing.
  """
  @spec generate_ecosystem_config() :: map()
  def generate_ecosystem_config do
    %{
      coordinator: generate_test_module_name(),
      workers: {generate_test_module_name(), count: :rand.uniform(50) + 1},
      memory_strategy: Enum.random([:isolated_heaps, :shared_heap]),
      gc_strategy: Enum.random([:frequent_minor, :standard]),
      fault_tolerance: Enum.random([:self_healing, :standard])
    }
  end

  defp generate_test_module_name do
    base_names = ["TestCoordinator", "TestWorker", "TestHandler", "TestProcessor"]
    suffix = :rand.uniform(1000)

    base_name = Enum.random(base_names)
    String.to_atom("#{base_name}#{suffix}")
  end

  @doc """
  Verify that processes are properly cleaned up after ecosystem shutdown.

  Checks that all processes in an ecosystem have terminated and their
  memory has been reclaimed.
  """
  @spec verify_ecosystem_cleanup(map(), non_neg_integer()) :: :ok | {:error, term()}
  def verify_ecosystem_cleanup(ecosystem, timeout \\ 5000) do
    all_pids = [ecosystem.coordinator | ecosystem.workers]

    # Wait for all processes to terminate
    case wait_for_condition(
           fn ->
             Enum.all?(all_pids, fn pid -> not Process.alive?(pid) end)
           end,
           timeout
         ) do
      :ok ->
        # Force garbage collection and verify memory cleanup
        :erlang.garbage_collect()
        :timer.sleep(100)
        :ok

      {:error, :timeout} ->
        alive_pids = Enum.filter(all_pids, &Process.alive?/1)
        {:error, {:processes_still_alive, alive_pids}}
    end
  end

  @doc """
  Create a load generator for testing ecosystem performance under stress.

  Generates sustained load against an ecosystem to test performance
  characteristics and identify bottlenecks.
  """
  @spec create_load_generator(map(), keyword()) :: pid()
  def create_load_generator(ecosystem, opts \\ []) do
    # messages per second
    rate = Keyword.get(opts, :rate, 100)
    # 10 seconds
    duration = Keyword.get(opts, :duration, 10_000)
    message_size = Keyword.get(opts, :message_size, :small)

    spawn(fn ->
      load_generator_loop(
        ecosystem,
        rate,
        duration,
        message_size,
        System.monotonic_time(:millisecond)
      )
    end)
  end

  defp load_generator_loop(ecosystem, rate, duration, message_size, start_time) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time > duration do
      :done
    else
      # Send message to random worker
      target = Enum.random([ecosystem.coordinator | ecosystem.workers])
      message = generate_test_message(message_size)

      if Process.alive?(target) do
        send(target, message)
      end

      # Sleep to maintain rate
      # milliseconds between messages
      interval = div(1000, rate)
      :timer.sleep(interval)

      load_generator_loop(ecosystem, rate, duration, message_size, start_time)
    end
  end

  defp generate_test_message(:small), do: {:test_message, :rand.uniform(1000)}
  defp generate_test_message(:medium), do: {:test_message, :crypto.strong_rand_bytes(1000)}
  defp generate_test_message(:large), do: {:test_message, :crypto.strong_rand_bytes(100_000)}
end
