defmodule MABEAM.AgentSupervisor do
  @moduledoc """
  Dynamic supervisor for MABEAM agents with enhanced monitoring and resource management.

  Provides supervised execution of MABEAM agents with automatic restarts, performance
  monitoring, and resource management. Integrates with MABEAM.Agent for
  agent lifecycle management while adding supervision layer.

  ## Features

  - Dynamic agent supervision with automatic restarts
  - Performance monitoring and resource tracking
  - Graceful shutdown and cleanup
  - Integration with Foundation process registry
  - Supervision metrics and health reporting
  - Resource usage monitoring and alerts

  ## Usage

      # Start an agent under supervision
      {:ok, pid} = AgentSupervisor.start_agent(:my_agent)

      # Stop a supervised agent
      :ok = AgentSupervisor.stop_agent(:my_agent)

      # Monitor agent performance
      metrics = AgentSupervisor.get_agent_performance(:my_agent)

      # Get system overview
      overview = AgentSupervisor.get_system_performance()
  """

  use DynamicSupervisor
  require Logger

  alias MABEAM.Agent
  alias Foundation.ProcessRegistry

  @type agent_id :: atom()
  @type supervision_metrics :: %{
          total_agents: non_neg_integer(),
          running_agents: non_neg_integer(),
          failed_agents: non_neg_integer(),
          restart_count: non_neg_integer(),
          agent_uptime: %{agent_id() => non_neg_integer()}
        }
  @type performance_metrics :: %{
          memory_usage: non_neg_integer(),
          message_queue_length: non_neg_integer(),
          reductions: non_neg_integer(),
          uptime_ms: non_neg_integer()
        }
  @type system_performance :: %{
          total_agents: non_neg_integer(),
          total_memory_usage: non_neg_integer(),
          average_message_queue_length: float(),
          top_memory_consumers: [%{agent_id: agent_id(), memory: non_neg_integer()}],
          agents_by_capability: %{atom() => non_neg_integer()}
        }

  # Registry key for tracking supervised agents
  @supervised_agents_key {:agent, :mabeam_supervised_agents}

  ## Public API

  @doc """
  Start the AgentSupervisor.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start an agent under supervision.

  The agent must be registered first using MABEAM.Agent.register_agent/1.

  ## Parameters
  - `agent_id` - The ID of the registered agent to start

  ## Returns
  - `{:ok, pid}` - Agent started successfully under supervision
  - `{:error, reason}` - Failed to start agent

  ## Examples

      {:ok, pid} = AgentSupervisor.start_agent(:my_worker)
  """
  @spec start_agent(agent_id()) ::
          {:ok, pid()}
          | {:error, :agent_not_registered | :already_running | :missing_module | term()}
  def start_agent(agent_id) do
    # Get agent config directly from AgentRegistry to avoid circular dependency
    with {:ok, agent_config} <- MABEAM.AgentRegistry.get_agent_config(agent_id),
         {:ok, agent_info_full} <- MABEAM.AgentRegistry.get_agent_status(agent_id) do
      # Build a simple agent info structure for validation and child spec
      agent_info = %{
        id: agent_id,
        module: agent_config.module,
        args: get_in(agent_config, [:config, :args]) || [],
        status: agent_info_full.status
      }

      with :ok <- validate_agent_startable(agent_info),
           {:ok, child_spec} <- build_agent_child_spec(agent_info),
           {:ok, pid} <- DynamicSupervisor.start_child(__MODULE__, child_spec) do
        # Track the supervised agent
        do_track_supervised_agent(agent_id, pid)

        # Update agent status to running in AgentRegistry directly
        GenServer.cast(MABEAM.AgentRegistry, {:update_agent_status, agent_id, pid, :running})

        {:ok, pid}
      else
        {:error, reason} ->
          Logger.error("Failed to start supervised agent #{agent_id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_found} ->
        Logger.error("Agent #{agent_id} not found in registry")
        {:error, :agent_not_registered}

      {:error, reason} ->
        Logger.error("Failed to get agent config for #{agent_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop a supervised agent gracefully.

  This function is synchronous and will not return until the agent process
  is confirmed to be terminated and removed from supervision, following
  proper OTP coordination principles.

  ## Parameters
  - `agent_id` - The ID of the agent to stop

  ## Returns
  - `:ok` - Agent stopped successfully
  - `{:error, reason}` - Failed to stop agent

  ## Examples

      :ok = AgentSupervisor.stop_agent(:my_worker)
  """
  @spec stop_agent(agent_id()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    case get_supervised_agent_pid(agent_id) do
      {:ok, pid} ->
        # Monitor the process to get synchronous notification when it dies
        monitor_ref = Process.monitor(pid)

        # DynamicSupervisor.terminate_child expects the child PID, not ID
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            # Wait for the process to actually terminate
            receive do
              {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
                # Process confirmed dead, now wait for supervisor cleanup
                wait_for_child_removal(pid)
                untrack_supervised_agent(agent_id)
                Agent.update_agent_status(agent_id, nil, :stopped)
                :ok
            after
              5000 ->
                # Timeout - force kill and clean up
                Process.demonitor(monitor_ref, [:flush])
                if Process.alive?(pid), do: Process.exit(pid, :kill)
                wait_for_child_removal(pid)
                untrack_supervised_agent(agent_id)
                Agent.update_agent_status(agent_id, nil, :stopped)
                :ok
            end

          {:error, :not_found} ->
            # Child not found in supervisor, use direct termination
            if Process.alive?(pid) do
              # Use proper OTP shutdown - trust the process to handle :shutdown
              Process.exit(pid, :shutdown)

              # Wait for confirmation
              receive do
                {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
                  # Process confirmed dead
                  :ok
              after
                5000 ->
                  # Force kill if graceful shutdown failed
                  Process.demonitor(monitor_ref, [:flush])
                  if Process.alive?(pid), do: Process.exit(pid, :kill)
                  :ok
              end
            else
              # Process already dead
              Process.demonitor(monitor_ref, [:flush])
            end

            # Even for direct termination, wait for supervisor cleanup
            wait_for_child_removal(pid)
            untrack_supervised_agent(agent_id)
            Agent.update_agent_status(agent_id, nil, :stopped)
            :ok
        end

      {:error, :not_found} ->
        {:error, :agent_not_supervised}
    end
  end

  @doc """
  Update agent configuration and restart with new config.

  ## Parameters
  - `agent_id` - The ID of the agent to update
  - `new_config` - New configuration map

  ## Returns
  - `:ok` - Agent updated successfully
  - `{:error, reason}` - Failed to update agent

  ## Examples

      new_config = %{id: :my_worker, type: :worker, module: MyWorker, args: [new: :config]}
      :ok = AgentSupervisor.update_agent_config(:my_worker, new_config)
  """
  @spec update_agent_config(agent_id(), map()) :: :ok | {:error, term()}
  def update_agent_config(agent_id, new_config) do
    with :ok <- stop_agent(agent_id),
         :ok <- Agent.unregister_agent(agent_id),
         :ok <- Agent.register_agent(new_config),
         {:ok, _pid} <- start_agent(agent_id) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the PID of a supervised agent.

  ## Parameters
  - `agent_id` - The ID of the agent

  ## Returns
  - `{:ok, pid}` - Agent PID found
  - `{:error, :not_found}` - Agent not supervised

  ## Examples

      {:ok, pid} = AgentSupervisor.get_agent_pid(:my_worker)
  """
  @spec get_agent_pid(agent_id()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent_pid(agent_id) do
    get_supervised_agent_pid(agent_id)
  end

  @doc """
  Get supervision metrics for all agents.

  Returns detailed metrics about supervised agents including restart counts,
  uptime, and status information.

  ## Returns
  - `supervision_metrics()` - Detailed supervision metrics

  ## Examples

      metrics = AgentSupervisor.get_supervision_metrics()
      # => %{total_agents: 5, running_agents: 4, failed_agents: 1, ...}
  """
  @spec get_supervision_metrics() :: supervision_metrics()
  def get_supervision_metrics do
    supervised_agents = get_all_supervised_agents()
    children = DynamicSupervisor.which_children(__MODULE__)

    running_count =
      Enum.count(children, fn {_, pid, _, _} ->
        is_pid(pid) and Process.alive?(pid)
      end)

    agent_uptime = calculate_agent_uptimes(supervised_agents)

    %{
      total_agents: map_size(supervised_agents),
      running_agents: running_count,
      failed_agents: map_size(supervised_agents) - running_count,
      restart_count: get_restart_count(),
      agent_uptime: agent_uptime
    }
  end

  @doc """
  Get performance metrics for a specific agent.

  ## Parameters
  - `agent_id` - The ID of the agent

  ## Returns
  - `performance_metrics()` - Agent performance metrics
  - `{:error, :not_found}` - Agent not found

  ## Examples

      metrics = AgentSupervisor.get_agent_performance(:my_worker)
      # => %{memory_usage: 1024, message_queue_length: 0, ...}
  """
  @spec get_agent_performance(agent_id()) :: performance_metrics() | {:error, :not_found}
  def get_agent_performance(agent_id) do
    case get_supervised_agent_pid(agent_id) do
      {:ok, pid} ->
        %{
          memory_usage: get_process_memory(pid),
          message_queue_length: get_message_queue_length(pid),
          reductions: get_process_reductions(pid),
          uptime_ms: get_process_uptime(agent_id)
        }

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Get system-wide performance overview.

  Returns aggregated performance metrics for all supervised agents.

  ## Returns
  - `system_performance()` - System performance overview

  ## Examples

      overview = AgentSupervisor.get_system_performance()
      # => %{total_agents: 10, total_memory_usage: 10240, ...}
  """
  @spec get_system_performance() :: system_performance()
  def get_system_performance do
    supervised_agents = get_all_supervised_agents()
    children = DynamicSupervisor.which_children(__MODULE__)

    # Collect performance data for all agents
    agent_performances =
      Enum.map(supervised_agents, fn {agent_id, _pid} ->
        case get_agent_performance(agent_id) do
          {:error, :not_found} -> nil
          metrics -> {agent_id, metrics}
        end
      end)
      |> Enum.reject(&is_nil/1)

    total_memory =
      agent_performances
      |> Enum.map(fn {_id, metrics} -> metrics.memory_usage end)
      |> Enum.sum()

    avg_queue_length =
      case agent_performances do
        [] ->
          0.0

        performances ->
          total_queue =
            performances
            |> Enum.map(fn {_id, metrics} -> metrics.message_queue_length end)
            |> Enum.sum()

          total_queue / length(performances)
      end

    top_memory_consumers =
      agent_performances
      |> Enum.map(fn {agent_id, metrics} -> %{agent_id: agent_id, memory: metrics.memory_usage} end)
      |> Enum.sort_by(& &1.memory, :desc)
      |> Enum.take(5)

    agents_by_capability = calculate_agents_by_capability()

    %{
      total_agents: length(children),
      total_memory_usage: total_memory,
      average_message_queue_length: avg_queue_length,
      top_memory_consumers: top_memory_consumers,
      agents_by_capability: agents_by_capability
    }
  end

  ## DynamicSupervisor Callbacks

  @impl true
  def init(_opts) do
    # Initialize tracking for supervised agents
    initialize_agent_tracking()

    Logger.info("MABEAM Agent Supervisor started")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end

  ## Agent Tracking (Direct Function Calls)
  # Note: DynamicSupervisor doesn't support GenServer callbacks
  # Use direct function calls for tracking instead

  @doc """
  Track a supervised agent for internal use.
  Called by AgentRegistry to avoid circular dependencies.
  """
  @spec track_supervised_agent(agent_id(), pid()) :: :ok
  def track_supervised_agent(agent_id, pid) do
    do_track_supervised_agent(agent_id, pid)
  end

  ## Private Functions

  defp validate_agent_startable(agent_info) do
    cond do
      agent_info.status == :running ->
        {:error, :already_running}

      agent_info.module == nil ->
        {:error, :missing_module}

      true ->
        :ok
    end
  end

  defp build_agent_child_spec(agent_info) do
    child_spec = %{
      id: agent_info.id,
      start: {agent_info.module, :start_link, [agent_info.args]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    {:ok, child_spec}
  end

  defp do_track_supervised_agent(agent_id, pid) do
    supervised_agents = get_all_supervised_agents()

    updated_agents =
      Map.put(supervised_agents, agent_id, %{
        pid: pid,
        started_at: System.monotonic_time(:millisecond),
        restart_count: 0
      })

    # Update or register the tracking data
    case ProcessRegistry.lookup(:production, @supervised_agents_key) do
      {:ok, _existing_pid} ->
        ProcessRegistry.unregister(:production, @supervised_agents_key)

        ProcessRegistry.register(:production, @supervised_agents_key, self(), %{
          supervised_agents: updated_agents
        })

      :error ->
        ProcessRegistry.register(:production, @supervised_agents_key, self(), %{
          supervised_agents: updated_agents
        })
    end
  end

  defp untrack_supervised_agent(agent_id) do
    supervised_agents = get_all_supervised_agents()
    updated_agents = Map.delete(supervised_agents, agent_id)

    case ProcessRegistry.lookup(:production, @supervised_agents_key) do
      {:ok, _existing_pid} ->
        ProcessRegistry.unregister(:production, @supervised_agents_key)

        ProcessRegistry.register(:production, @supervised_agents_key, self(), %{
          supervised_agents: updated_agents
        })

      :error ->
        # No tracking entry exists, nothing to update
        :ok
    end
  end

  defp get_supervised_agent_pid(agent_id) do
    supervised_agents = get_all_supervised_agents()

    case Map.get(supervised_agents, agent_id) do
      %{pid: pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :not_found}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp get_all_supervised_agents do
    case ProcessRegistry.get_metadata(:production, @supervised_agents_key) do
      {:ok, %{supervised_agents: agents}} when is_map(agents) -> agents
      _ -> %{}
    end
  end

  defp initialize_agent_tracking do
    case ProcessRegistry.lookup(:production, @supervised_agents_key) do
      :error ->
        ProcessRegistry.register(:production, @supervised_agents_key, self(), %{
          supervised_agents: %{}
        })

      {:ok, _pid} ->
        # Already initialized
        :ok
    end
  end

  defp calculate_agent_uptimes(supervised_agents) do
    current_time = System.monotonic_time(:millisecond)

    Enum.reduce(supervised_agents, %{}, fn {agent_id, agent_data}, acc ->
      uptime = current_time - agent_data.started_at
      Map.put(acc, agent_id, uptime)
    end)
  end

  defp get_restart_count do
    # This would be tracked more sophisticatedly in production
    # For now, return 0 as a placeholder
    0
  end

  defp calculate_agents_by_capability do
    try do
      Agent.list_agents()
      |> Enum.flat_map(fn agent -> agent.capabilities || [] end)
      |> Enum.frequencies()
    rescue
      _ -> %{}
    end
  end

  defp get_process_memory(pid) when is_pid(pid) do
    case Process.info(pid, :memory) do
      {:memory, memory} -> memory
      nil -> 0
    end
  end

  defp get_message_queue_length(pid) when is_pid(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, length} -> length
      nil -> 0
    end
  end

  defp get_process_reductions(pid) when is_pid(pid) do
    case Process.info(pid, :reductions) do
      {:reductions, reductions} -> reductions
      nil -> 0
    end
  end

  defp get_process_uptime(agent_id) do
    supervised_agents = get_all_supervised_agents()
    current_time = System.monotonic_time(:millisecond)

    case Map.get(supervised_agents, agent_id) do
      %{started_at: started_at} -> current_time - started_at
      nil -> 0
    end
  end

  # Wait for the child to be completely removed from supervisor's children list
  defp wait_for_child_removal(pid, timeout \\ 2000) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_child_removal_loop(pid, start_time, timeout)
  end

  defp wait_for_child_removal_loop(pid, start_time, timeout) do
    children = DynamicSupervisor.which_children(__MODULE__)

    case Enum.find(children, fn {_, child_pid, _, _} -> child_pid == pid end) do
      nil ->
        # Child removed from supervisor, we're done
        :ok

      _child_spec ->
        # Child still in supervisor list, check timeout
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed >= timeout do
          # Timeout reached, but this is not an error - supervisor cleanup can be async
          :ok
        else
          # Wait a bit and check again
          Process.sleep(10)
          wait_for_child_removal_loop(pid, start_time, timeout)
        end
    end
  end
end
