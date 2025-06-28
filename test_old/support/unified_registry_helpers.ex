defmodule Foundation.TestHelpers.UnifiedRegistry do
  @moduledoc """
  Unified test helpers for the consolidated Foundation.ProcessRegistry.

  This module provides a single, consistent interface for testing both basic
  service registration and advanced agent management functionality across
  different backend implementations.

  ## Features

  - **Unified API**: Single interface for all registry testing needs
  - **Backend Agnostic**: Works with ETS, Registry, and future backends
  - **Agent Support**: Comprehensive agent lifecycle testing helpers
  - **Performance Testing**: Built-in utilities for load and performance testing
  - **Automatic Cleanup**: Safe and reliable test isolation

  ## Usage

      defmodule MyRegistryTest do
        use ExUnit.Case, async: false
        import Foundation.TestHelpers.UnifiedRegistry

        setup do
          setup_test_namespace()
        end

        test "service registration", %{namespace: namespace} do
          assert :ok = register_test_service(namespace, :my_service, self())
          assert_registered(namespace, :my_service)
        end
      end
  """

  alias Foundation.ProcessRegistry

  @type namespace :: Foundation.ProcessRegistry.namespace()
  @type service_name :: Foundation.ProcessRegistry.service_name()
  @type test_ref :: reference()
  @type agent_config :: map()

  # ============================================================================
  # Basic Registry Operations
  # ============================================================================

  @doc """
  Set up a test namespace with automatic cleanup.

  ## Options
  - `:cleanup_on_exit` - Automatically clean up on test exit (default: true)
  - `:namespace_type` - Type of namespace to create (default: :test)

  ## Returns
  - `%{namespace: namespace, test_ref: test_ref}`

  ## Examples

      setup do
        setup_test_namespace()
      end

      setup do
        setup_test_namespace(cleanup_on_exit: false)
      end
  """
  @spec setup_test_namespace(keyword()) :: %{namespace: namespace(), test_ref: test_ref()}
  def setup_test_namespace(opts \\ []) do
    cleanup_on_exit = Keyword.get(opts, :cleanup_on_exit, true)
    test_ref = make_ref()
    namespace = {:test, test_ref}

    if cleanup_on_exit do
      ExUnit.Callbacks.on_exit(fn ->
        cleanup_test_namespace(test_ref)
      end)
    end

    %{namespace: namespace, test_ref: test_ref}
  end

  @doc """
  Clean up a test namespace by terminating all registered processes.

  ## Parameters
  - `test_ref` - The test reference from setup_test_namespace/1

  ## Examples

      cleanup_test_namespace(test_ref)
  """
  @spec cleanup_test_namespace(test_ref()) :: :ok
  def cleanup_test_namespace(test_ref) do
    ProcessRegistry.cleanup_test_namespace(test_ref)
  end

  @doc """
  Register a test service with optional metadata.

  ## Parameters
  - `namespace` - The test namespace
  - `service` - Service name to register
  - `pid` - Process to register (defaults to self())
  - `metadata` - Optional metadata map

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      assert :ok = register_test_service(namespace, :my_service, self())
      assert :ok = register_test_service(namespace, :worker, pid, %{type: :computation})
  """
  @spec register_test_service(namespace(), service_name(), pid(), map()) ::
          :ok | {:error, term()}
  def register_test_service(namespace, service, pid \\ nil, metadata \\ %{}) do
    actual_pid = pid || self()
    ProcessRegistry.register(namespace, service, actual_pid, metadata)
  end

  # ============================================================================
  # Agent-Specific Operations
  # ============================================================================

  @doc """
  Create a test agent configuration.

  ## Parameters
  - `id` - Agent identifier
  - `module` - Agent module (defaults to a test worker)
  - `args` - Initialization arguments
  - `opts` - Additional options

  ## Options
  - `:capabilities` - List of agent capabilities
  - `:type` - Agent type (`:worker`, `:coordinator`, etc.)
  - `:restart_policy` - Restart policy (`:permanent`, `:temporary`, `:transient`)
  - `:metadata` - Additional metadata

  ## Returns
  - Agent configuration map

  ## Examples

      config = create_test_agent_config(:worker1, TestWorker, [])
      config = create_test_agent_config(:ml_agent, MLWorker, [],
        capabilities: [:compute, :ml],
        type: :ml_worker
      )
  """
  @spec create_test_agent_config(atom(), module(), list(), keyword()) :: agent_config()
  def create_test_agent_config(
        id,
        module \\ Foundation.TestHelpers.TestWorker,
        args \\ [],
        opts \\ []
      ) do
    capabilities = Keyword.get(opts, :capabilities, [])
    agent_type = Keyword.get(opts, :type, :worker)
    restart_policy = Keyword.get(opts, :restart_policy, :temporary)
    metadata = Keyword.get(opts, :metadata, %{})

    %{
      id: id,
      type: agent_type,
      module: module,
      args: args,
      capabilities: capabilities,
      restart_policy: restart_policy,
      metadata: Map.merge(%{test_agent: true, created_at: DateTime.utc_now()}, metadata)
    }
  end

  @doc """
  Register a test agent using its configuration.

  ## Parameters
  - `config` - Agent configuration from create_test_agent_config/4
  - `namespace` - Target namespace (defaults to production)

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      config = create_test_agent_config(:test_agent, TestWorker, [])
      assert :ok = register_test_agent(config, namespace)
  """
  @spec register_test_agent(agent_config(), namespace()) :: :ok | {:error, term()}
  def register_test_agent(config, namespace \\ :production) do
    service_name = {:agent, config.id}

    agent_metadata = %{
      type: :mabeam_agent,
      agent_type: config.type,
      capabilities: config.capabilities,
      module: config.module,
      args: config.args,
      restart_policy: config.restart_policy,
      config: config
    }

    merged_metadata = Map.merge(agent_metadata, config.metadata)
    register_test_service(namespace, service_name, self(), merged_metadata)
  end

  @doc """
  Start a test agent process and register it.

  ## Parameters
  - `agent_id` - Agent identifier
  - `namespace` - Target namespace
  - `opts` - Agent options

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, pid} = start_test_agent(:worker1, namespace)
      {:ok, pid} = start_test_agent(:ml_agent, namespace, capabilities: [:ml])
  """
  @spec start_test_agent(atom(), namespace(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_test_agent(agent_id, namespace \\ :production, opts \\ []) do
    config = create_test_agent_config(agent_id, Foundation.TestHelpers.TestWorker, [], opts)

    case Task.start(fn ->
           Process.flag(:trap_exit, true)

           receive do
             :shutdown -> :ok
             _ -> start_test_agent(agent_id, namespace, opts)
           end
         end) do
      {:ok, pid} ->
        service_name = {:agent, agent_id}

        agent_metadata = %{
          type: :mabeam_agent,
          agent_type: config.type,
          capabilities: config.capabilities,
          module: config.module,
          args: config.args,
          restart_policy: config.restart_policy,
          config: config
        }

        case ProcessRegistry.register(namespace, service_name, pid, agent_metadata) do
          :ok ->
            {:ok, pid}

          error ->
            Process.exit(pid, :shutdown)
            error
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Performance Testing Utilities
  # ============================================================================

  @doc """
  Create multiple test agents for load testing.

  ## Parameters
  - `count` - Number of agents to create
  - `opts` - Options for agent creation

  ## Options
  - `:base_name` - Base name for agent IDs (default: :load_test_agent)
  - `:capabilities` - Capabilities for all agents
  - `:start_processes` - Whether to start actual processes (default: false)

  ## Returns
  - List of agent configurations or `{config, pid}` tuples if processes started

  ## Examples

      configs = create_load_test_agents(100)
      agents = create_load_test_agents(50, start_processes: true)
  """
  @spec create_load_test_agents(pos_integer(), keyword()) :: [
          agent_config() | {agent_config(), pid()}
        ]
  def create_load_test_agents(count, opts \\ []) when count > 0 do
    base_name = Keyword.get(opts, :base_name, :load_test_agent)
    start_processes = Keyword.get(opts, :start_processes, false)

    1..count
    |> Enum.map(fn i ->
      agent_id = :"#{base_name}_#{i}"
      config = create_test_agent_config(agent_id, Foundation.TestHelpers.TestWorker, [], opts)

      if start_processes do
        {:ok, pid} = Task.start(fn -> Process.sleep(:infinity) end)
        {config, pid}
      else
        config
      end
    end)
  end

  @doc """
  Benchmark registry operations with configurable load.

  ## Parameters
  - `operations` - List of operations to benchmark
  - `opts` - Benchmark options

  ## Options
  - `:iterations` - Number of iterations per operation (default: 1000)
  - `:warmup` - Warmup iterations (default: 100)
  - `:concurrency` - Number of concurrent processes (default: 1)

  ## Operations
  - `:register` - Benchmark registration operations
  - `:lookup` - Benchmark lookup operations
  - `:update_metadata` - Benchmark metadata updates
  - `:unregister` - Benchmark unregistration

  ## Returns
  - Map with timing results for each operation

  ## Examples

      results = benchmark_registry_operations([:register, :lookup])
      results = benchmark_registry_operations([:all], iterations: 5000, concurrency: 10)
  """
  @spec benchmark_registry_operations([atom()], keyword()) :: map()
  def benchmark_registry_operations(operations, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    warmup = Keyword.get(opts, :warmup, 100)
    concurrency = Keyword.get(opts, :concurrency, 1)

    %{namespace: namespace, test_ref: test_ref} = setup_test_namespace()

    try do
      benchmark_results = %{}

      # Warmup
      if warmup > 0 do
        run_benchmark_warmup(namespace, warmup)
      end

      # Run benchmarks for each operation
      operations
      |> expand_operations()
      |> Enum.reduce(benchmark_results, fn operation, acc ->
        result = run_operation_benchmark(operation, namespace, iterations, concurrency)
        Map.put(acc, operation, result)
      end)
    after
      cleanup_test_namespace(test_ref)
    end
  end

  # ============================================================================
  # Assertion Helpers
  # ============================================================================

  @doc """
  Assert that a service is registered in the namespace.

  ## Parameters
  - `namespace` - Namespace to check
  - `service` - Service name to verify

  ## Examples

      assert_registered(namespace, :my_service)
      assert_registered(namespace, {:agent, :worker1})
  """
  @spec assert_registered(namespace(), service_name()) :: true
  def assert_registered(namespace, service) do
    case ProcessRegistry.lookup(namespace, service) do
      {:ok, _pid} ->
        true

      :error ->
        available_services = ProcessRegistry.list_services(namespace)

        ExUnit.Assertions.flunk("""
        Expected service #{inspect(service)} to be registered in namespace #{inspect(namespace)}.

        Available services: #{inspect(available_services)}
        """)
    end
  end

  @doc """
  Assert that a service is NOT registered in the namespace.

  ## Parameters
  - `namespace` - Namespace to check
  - `service` - Service name to verify absence

  ## Examples

      assert_not_registered(namespace, :missing_service)
  """
  @spec assert_not_registered(namespace(), service_name()) :: true
  def assert_not_registered(namespace, service) do
    case ProcessRegistry.lookup(namespace, service) do
      :error ->
        true

      {:ok, pid} ->
        ExUnit.Assertions.flunk("""
        Expected service #{inspect(service)} to NOT be registered in namespace #{inspect(namespace)}.

        Found registered to PID: #{inspect(pid)}
        """)
    end
  end

  @doc """
  Assert that a service has expected metadata.

  ## Parameters
  - `namespace` - Namespace containing the service
  - `service` - Service name
  - `expected_metadata` - Expected metadata map

  ## Examples

      assert_metadata_equals(namespace, :worker, %{type: :computation})
  """
  @spec assert_metadata_equals(namespace(), service_name(), map()) :: true
  def assert_metadata_equals(namespace, service, expected_metadata) do
    case ProcessRegistry.get_metadata(namespace, service) do
      {:ok, actual_metadata} ->
        if actual_metadata == expected_metadata do
          true
        else
          ExUnit.Assertions.flunk("""
          Metadata mismatch for service #{inspect(service)} in namespace #{inspect(namespace)}.

          Expected: #{inspect(expected_metadata)}
          Actual:   #{inspect(actual_metadata)}
          """)
        end

      {:error, :not_found} ->
        ExUnit.Assertions.flunk("""
        Service #{inspect(service)} not found in namespace #{inspect(namespace)} when checking metadata.
        """)
    end
  end

  @doc """
  Assert that an agent has the specified capabilities.

  ## Parameters
  - `agent_id` - Agent identifier
  - `capabilities` - Expected capabilities list
  - `namespace` - Namespace (defaults to :production)

  ## Examples

      assert_agent_has_capabilities(:ml_worker, [:compute, :ml])
  """
  @spec assert_agent_has_capabilities(atom(), [atom()], namespace()) :: true
  def assert_agent_has_capabilities(agent_id, capabilities, namespace \\ :production) do
    service_name = {:agent, agent_id}

    case ProcessRegistry.get_metadata(namespace, service_name) do
      {:ok, metadata} ->
        actual_capabilities = Map.get(metadata, :capabilities, [])

        missing_capabilities = capabilities -- actual_capabilities

        if missing_capabilities == [] do
          true
        else
          ExUnit.Assertions.flunk("""
          Agent #{inspect(agent_id)} missing expected capabilities.

          Expected: #{inspect(capabilities)}
          Actual:   #{inspect(actual_capabilities)}
          Missing:  #{inspect(missing_capabilities)}
          """)
        end

      {:error, :not_found} ->
        ExUnit.Assertions.flunk("""
        Agent #{inspect(agent_id)} not found in namespace #{inspect(namespace)}.
        """)
    end
  end

  @doc """
  Assert that an agent is running (registered and process alive).

  ## Parameters
  - `agent_id` - Agent identifier
  - `namespace` - Namespace (defaults to :production)

  ## Examples

      assert_agent_running(:worker1)
      assert_agent_running(:ml_agent, namespace)
  """
  @spec assert_agent_running(atom(), namespace()) :: true
  def assert_agent_running(agent_id, namespace \\ :production) do
    service_name = {:agent, agent_id}

    case ProcessRegistry.lookup(namespace, service_name) do
      {:ok, pid} ->
        if Process.alive?(pid) do
          true
        else
          ExUnit.Assertions.flunk("""
          Agent #{inspect(agent_id)} is registered but process #{inspect(pid)} is not alive.
          """)
        end

      :error ->
        ExUnit.Assertions.flunk("""
        Agent #{inspect(agent_id)} is not registered in namespace #{inspect(namespace)}.
        """)
    end
  end

  # ============================================================================
  # Cleanup Utilities
  # ============================================================================

  @doc """
  Clean up all test agents in a namespace.

  ## Parameters
  - `namespace` - Namespace to clean up

  ## Examples

      cleanup_all_test_agents(namespace)
  """
  @spec cleanup_all_test_agents(namespace()) :: :ok
  def cleanup_all_test_agents(namespace) do
    services = ProcessRegistry.list_services_with_metadata(namespace)

    agent_services =
      services
      |> Enum.filter(fn {_service, metadata} ->
        Map.get(metadata, :test_agent, false)
      end)
      |> Enum.map(fn {service, _metadata} -> service end)

    Enum.each(agent_services, fn service ->
      case ProcessRegistry.lookup(namespace, service) do
        {:ok, pid} ->
          if Process.alive?(pid) do
            Process.exit(pid, :shutdown)
          end

        :error ->
          :ok
      end

      ProcessRegistry.unregister(namespace, service)
    end)

    :ok
  end

  @doc """
  Reset registry state for testing.

  This is a utility for tests that need a completely clean registry state.
  Use with caution as it affects global state.

  ## Examples

      reset_registry_state()
  """
  @spec reset_registry_state() :: :ok
  def reset_registry_state do
    # This is a test-only utility - in a real implementation,
    # this would clean up any global registry state

    # For now, we'll just ensure the backup table is clean
    case :ets.info(:process_registry_backup) do
      :undefined ->
        :ok

      _ ->
        :ets.delete_all_objects(:process_registry_backup)
        :ok
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Expand operation shortcuts like :all into specific operations
  defp expand_operations(operations) do
    Enum.flat_map(operations, fn
      :all -> [:register, :lookup, :update_metadata, :unregister]
      op -> [op]
    end)
  end

  # Run warmup iterations to stabilize timing
  defp run_benchmark_warmup(namespace, warmup_count) do
    1..warmup_count
    |> Enum.each(fn i ->
      service = :"warmup_service_#{i}"
      :ok = register_test_service(namespace, service, self())
      {:ok, _} = ProcessRegistry.lookup(namespace, service)
      :ok = ProcessRegistry.unregister(namespace, service)
    end)
  end

  # Run benchmark for a specific operation
  defp run_operation_benchmark(operation, namespace, iterations, concurrency) do
    if concurrency == 1 do
      run_single_threaded_benchmark(operation, namespace, iterations)
    else
      run_concurrent_benchmark(operation, namespace, iterations, concurrency)
    end
  end

  # Single-threaded benchmark
  defp run_single_threaded_benchmark(operation, namespace, iterations) do
    {time_microseconds, _} =
      :timer.tc(fn ->
        1..iterations
        |> Enum.each(fn i ->
          run_single_operation(operation, namespace, i)
        end)
      end)

    %{
      operation: operation,
      iterations: iterations,
      total_time_us: time_microseconds,
      avg_time_us: time_microseconds / iterations,
      ops_per_second: iterations / (time_microseconds / 1_000_000)
    }
  end

  # Concurrent benchmark
  defp run_concurrent_benchmark(operation, namespace, iterations, concurrency) do
    iterations_per_process = div(iterations, concurrency)

    {time_microseconds, _} =
      :timer.tc(fn ->
        1..concurrency
        |> Task.async_stream(
          fn _proc_id ->
            1..iterations_per_process
            |> Enum.each(fn i ->
              run_single_operation(operation, namespace, i)
            end)
          end,
          max_concurrency: concurrency
        )
        |> Enum.to_list()
      end)

    total_ops = iterations_per_process * concurrency

    %{
      operation: operation,
      iterations: total_ops,
      concurrency: concurrency,
      total_time_us: time_microseconds,
      avg_time_us: time_microseconds / total_ops,
      ops_per_second: total_ops / (time_microseconds / 1_000_000)
    }
  end

  # Execute a single operation for benchmarking
  defp run_single_operation(operation, namespace, i) do
    service = :"bench_service_#{i}_#{System.unique_integer()}"
    metadata = %{benchmark: true, iteration: i}

    case operation do
      :register ->
        :ok = register_test_service(namespace, service, self(), metadata)

      :lookup ->
        # Pre-register for lookup test
        :ok = register_test_service(namespace, service, self(), metadata)
        {:ok, _} = ProcessRegistry.lookup(namespace, service)

      :update_metadata ->
        # Pre-register for update test
        :ok = register_test_service(namespace, service, self(), %{})
        new_metadata = Map.put(metadata, :updated, true)
        :ok = ProcessRegistry.update_metadata(namespace, service, new_metadata)

      :unregister ->
        # Pre-register for unregister test
        :ok = register_test_service(namespace, service, self(), metadata)
        :ok = ProcessRegistry.unregister(namespace, service)
    end
  end
end
