defmodule Foundation.TestServices do
  @moduledoc """
  Test service doubles for isolated supervision testing.

  These modules provide the same interface as JidoFoundation services
  but support custom names and isolated registry registration, enabling
  true test isolation for supervision crash recovery testing.
  """

  defmodule SchedulerManager do
    @moduledoc """
    Test double for JidoFoundation.SchedulerManager.

    Provides the same interface but supports custom names and registry registration.
    """

    use GenServer
    require Logger

    def start_link(opts \\ []) do
      name = Keyword.get(opts, :name, __MODULE__)
      registry = Keyword.get(opts, :registry)

      GenServer.start_link(__MODULE__, {opts, registry}, name: name)
    end

    def init({_opts, registry}) do
      # Register with test registry if provided
      if registry do
        Registry.register(registry, {:service, JidoFoundation.SchedulerManager}, %{
          test_service: true,
          original_module: JidoFoundation.SchedulerManager
        })
      end

      Logger.debug("TestServices.SchedulerManager started: #{inspect(self())}")

      # Minimal state to simulate a real service
      state = %{
        started_at: System.system_time(:millisecond),
        requests_handled: 0,
        registry: registry
      }

      {:ok, state}
    end

    def handle_call(:get_stats, _from, state) do
      stats = %{
        uptime: System.system_time(:millisecond) - state.started_at,
        requests_handled: state.requests_handled,
        status: :running
      }

      {:reply, stats, %{state | requests_handled: state.requests_handled + 1}}
    end

    def handle_call(_msg, _from, state) do
      {:reply, :ok, %{state | requests_handled: state.requests_handled + 1}}
    end

    def handle_cast(_msg, state) do
      {:noreply, state}
    end
  end

  defmodule TaskPoolManager do
    @moduledoc """
    Test double for JidoFoundation.TaskPoolManager.

    Provides the same interface but supports custom names and registry registration.
    """

    use GenServer
    require Logger

    def start_link(opts \\ []) do
      name = Keyword.get(opts, :name, __MODULE__)
      registry = Keyword.get(opts, :registry)

      GenServer.start_link(__MODULE__, {opts, registry}, name: name)
    end

    def init({_opts, registry}) do
      # Register with test registry if provided
      if registry do
        Registry.register(registry, {:service, JidoFoundation.TaskPoolManager}, %{
          test_service: true,
          original_module: JidoFoundation.TaskPoolManager
        })
      end

      Logger.debug("TestServices.TaskPoolManager started: #{inspect(self())}")

      # Simulate task pools
      state = %{
        started_at: System.system_time(:millisecond),
        pools: %{},
        tasks_executed: 0,
        registry: registry
      }

      {:ok, state}
    end

    def handle_call(:get_all_stats, _from, state) do
      stats = %{
        uptime: System.system_time(:millisecond) - state.started_at,
        active_pools: map_size(state.pools),
        tasks_executed: state.tasks_executed,
        status: :running
      }

      {:reply, stats, %{state | tasks_executed: state.tasks_executed + 1}}
    end

    def handle_call({:create_pool, [pool_name, config]}, _from, state) do
      new_pools = Map.put(state.pools, pool_name, config)
      {:reply, :ok, %{state | pools: new_pools}}
    end

    def handle_call({:get_pool_stats, [pool_name]}, _from, state) do
      case Map.get(state.pools, pool_name) do
        nil ->
          {:reply, {:error, :pool_not_found}, state}

        config ->
          stats =
            Map.merge(config, %{
              active_tasks: 0,
              total_tasks: 0,
              status: :running
            })

          {:reply, {:ok, stats}, state}
      end
    end

    def handle_call({:execute_batch, [pool_name, data, fun, _opts]}, _from, state) do
      # Simulate batch execution
      case Map.get(state.pools, pool_name) do
        nil ->
          {:reply, {:error, :pool_not_found}, state}

        _config ->
          # Simple simulation of batch processing
          results =
            Enum.map(data, fn item ->
              try do
                {:ok, fun.(item)}
              rescue
                e -> {:error, e}
              end
            end)

          # Just return the results as a list for simplicity
          {:reply, {:ok, results}, %{state | tasks_executed: state.tasks_executed + length(data)}}
      end
    end

    def handle_call(_msg, _from, state) do
      {:reply, :ok, %{state | tasks_executed: state.tasks_executed + 1}}
    end

    def handle_cast(_msg, state) do
      {:noreply, state}
    end
  end

  defmodule SystemCommandManager do
    @moduledoc """
    Test double for JidoFoundation.SystemCommandManager.

    Provides the same interface but supports custom names and registry registration.
    """

    use GenServer
    require Logger

    def start_link(opts \\ []) do
      name = Keyword.get(opts, :name, __MODULE__)
      registry = Keyword.get(opts, :registry)

      GenServer.start_link(__MODULE__, {opts, registry}, name: name)
    end

    def init({_opts, registry}) do
      # Register with test registry if provided
      if registry do
        Registry.register(registry, {:service, JidoFoundation.SystemCommandManager}, %{
          test_service: true,
          original_module: JidoFoundation.SystemCommandManager
        })
      end

      Logger.debug("TestServices.SystemCommandManager started: #{inspect(self())}")

      state = %{
        started_at: System.system_time(:millisecond),
        commands_executed: 0,
        registry: registry
      }

      {:ok, state}
    end

    def handle_call(:get_stats, _from, state) do
      stats = %{
        uptime: System.system_time(:millisecond) - state.started_at,
        commands_executed: state.commands_executed,
        status: :running
      }

      {:reply, stats, %{state | commands_executed: state.commands_executed + 1}}
    end

    def handle_call(_msg, _from, state) do
      {:reply, :ok, %{state | commands_executed: state.commands_executed + 1}}
    end

    def handle_cast(_msg, state) do
      {:noreply, state}
    end
  end

  defmodule CoordinationManager do
    @moduledoc """
    Test double for JidoFoundation.CoordinationManager.

    Provides the same interface but supports custom names and registry registration.
    """

    use GenServer
    require Logger

    def start_link(opts \\ []) do
      name = Keyword.get(opts, :name, __MODULE__)
      registry = Keyword.get(opts, :registry)

      GenServer.start_link(__MODULE__, {opts, registry}, name: name)
    end

    def init({_opts, registry}) do
      # Register with test registry if provided
      if registry do
        Registry.register(registry, {:service, JidoFoundation.CoordinationManager}, %{
          test_service: true,
          original_module: JidoFoundation.CoordinationManager
        })
      end

      Logger.debug("TestServices.CoordinationManager started: #{inspect(self())}")

      state = %{
        started_at: System.system_time(:millisecond),
        coordinations_handled: 0,
        registry: registry
      }

      {:ok, state}
    end

    def handle_call(:get_stats, _from, state) do
      stats = %{
        uptime: System.system_time(:millisecond) - state.started_at,
        coordinations_handled: state.coordinations_handled,
        status: :running
      }

      {:reply, stats, %{state | coordinations_handled: state.coordinations_handled + 1}}
    end

    def handle_call(_msg, _from, state) do
      {:reply, :ok, %{state | coordinations_handled: state.coordinations_handled + 1}}
    end

    def handle_cast(_msg, state) do
      {:noreply, state}
    end
  end
end
