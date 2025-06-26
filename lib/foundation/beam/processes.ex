defmodule Foundation.BEAM.Processes do
  @moduledoc """
  BEAM-native process ecosystem management.

  This module provides process-first design patterns that embrace the BEAM's
  unique process model. Instead of thinking in terms of single GenServers,
  this module helps you create ecosystems of collaborating processes that
  leverage BEAM's lightweight process characteristics.

  ## Key Concepts

  - **Process Ecosystem**: A coordinated group of processes working together
  - **Memory Isolation**: Each process has its own heap for GC isolation
  - **Lightweight Spawning**: Processes start with tiny heaps but grow as needed
  - **Fault Isolation**: Process crashes don't affect other processes

  ## Examples

      # Spawn a simple ecosystem
      {:ok, ecosystem} = Foundation.BEAM.Processes.spawn_ecosystem(%{
        coordinator: MyCoordinator,
        workers: {MyWorker, count: 10},
        memory_strategy: :isolated_heaps
      })

      # Create a process for memory-intensive work
      Foundation.BEAM.Processes.isolate_memory_intensive_work(fn ->
        # This work happens in its own process with dedicated heap
        heavy_computation()
      end)
  """

  alias Foundation.ErrorContext
  alias Foundation.Types.Error

  @type ecosystem_config :: %{
          required(:coordinator) => module(),
          required(:workers) => {module(), keyword()},
          optional(:memory_strategy) => :isolated_heaps | :shared_heap,
          optional(:gc_strategy) => :frequent_minor | :standard,
          optional(:fault_tolerance) => :self_healing | :standard
        }

  @type ecosystem :: %{
          coordinator: pid(),
          workers: [pid()],
          monitors: [reference()],
          topology: :mesh | :tree | :ring,
          supervisor: pid() | nil,
          config: ecosystem_config()
        }

  @doc """
  Spawn an ecosystem of collaborating processes.

  Creates a coordinator process and a configurable number of worker processes
  that work together as an ecosystem. Each process has its own isolated heap
  for optimal garbage collection performance.

  **Note**: This function now uses proper OTP supervision via EcosystemSupervisor
  for improved reliability and automatic process restarts.

  ## Parameters

  - `config` - Configuration map defining the ecosystem structure

  ## Examples

      # Basic ecosystem
      {:ok, ecosystem} = spawn_ecosystem(%{
        coordinator: DataCoordinator,
        workers: {DataProcessor, count: 5}
      })

      # Advanced ecosystem with memory optimization
      {:ok, ecosystem} = spawn_ecosystem(%{
        coordinator: WorkerCoordinator,
        workers: {DataProcessor, count: 100},
        memory_strategy: :isolated_heaps,
        gc_strategy: :frequent_minor,
        fault_tolerance: :self_healing
      })
  """
  @spec spawn_ecosystem(ecosystem_config()) :: {:ok, ecosystem()} | {:error, Error.t()}
  def spawn_ecosystem(config) do
    context = ErrorContext.new(__MODULE__, :spawn_ecosystem, metadata: %{config: config})

    ErrorContext.with_context(context, fn ->
      case validate_config(config) do
        :ok ->
          # Use the new OTP-based EcosystemSupervisor when modules have proper GenServer interface
          # For test modules or backward compatibility, allow fallback with validation
          if has_proper_genserver_start_link?(config.coordinator) and
               has_proper_genserver_start_link?(elem(config.workers, 0)) do
            # Use new OTP supervision for proper GenServer modules
            ecosystem_id = :"ecosystem_#{:erlang.unique_integer([:positive])}"

            ecosystem_config = %{
              # Generate unique ID for this ecosystem
              id: ecosystem_id,
              coordinator: config.coordinator,
              workers: config.workers
            }

            case Foundation.BEAM.EcosystemSupervisor.start_link(ecosystem_config) do
              {:ok, supervisor_pid} ->
                # By the time we are here, the supervisor's init/1 has completed,
                # which means its children have been started. Trust OTP synchronous startup.
                case Foundation.BEAM.EcosystemSupervisor.get_coordinator(supervisor_pid) do
                  {:ok, coordinator_pid} ->
                    worker_pids = Foundation.BEAM.EcosystemSupervisor.list_workers(supervisor_pid)

                    # Build ecosystem structure for backward compatibility
                    ecosystem = %{
                      coordinator: coordinator_pid,
                      workers: worker_pids,
                      # No longer manually monitored
                      monitors: [],
                      topology: :tree,
                      # NEW: Add supervisor reference
                      supervisor: supervisor_pid,
                      config: config
                    }

                    {:ok, ecosystem}

                  {:error, reason} ->
                    # Handle the case where the coordinator failed to start or isn't found
                    # This is proper error handling, not a race condition.
                    {:error, {:coordinator_not_found, reason}}
                end

              {:error, error} ->
                {:error, error}
            end
          else
            # For test modules or backward compatibility
            # Issue a warning but continue with ecosystem supervisor
            require Logger

            Logger.warning(
              "Using OTP supervision for modules that may not be proper GenServers: #{config.coordinator}, #{elem(config.workers, 0)}"
            )

            ecosystem_id = :"ecosystem_#{:erlang.unique_integer([:positive])}"

            ecosystem_config = %{
              id: ecosystem_id,
              coordinator: config.coordinator,
              workers: config.workers
            }

            case Foundation.BEAM.EcosystemSupervisor.start_link(ecosystem_config) do
              {:ok, supervisor_pid} ->
                case Foundation.BEAM.EcosystemSupervisor.get_coordinator(supervisor_pid) do
                  {:ok, coordinator_pid} ->
                    worker_pids = Foundation.BEAM.EcosystemSupervisor.list_workers(supervisor_pid)

                    ecosystem = %{
                      coordinator: coordinator_pid,
                      workers: worker_pids,
                      monitors: [],
                      topology: :tree,
                      supervisor: supervisor_pid,
                      config: config
                    }

                    {:ok, ecosystem}

                  {:error, reason} ->
                    {:error, {:coordinator_not_found, reason}}
                end

              {:error, error} ->
                {:error, error}
            end
          end

        {:error, reason} ->
          {:error,
           Error.new(
             code: 3001,
             error_type: :validation_error,
             message: reason,
             severity: :high,
             context: %{validation_context: context}
           )}
      end
    end)
  end

  @doc """
  Isolate memory-intensive work in a dedicated process.

  Spawns a short-lived process specifically for memory-intensive operations.
  When the process completes and dies, its heap is automatically garbage
  collected, preventing memory pressure on other processes.

  ## Parameters

  - `work_fn` - Function to execute in isolation
  - `caller` - Optional PID to send results to (defaults to self())

  ## Examples

      # Isolate heavy computation
      Foundation.BEAM.Processes.isolate_memory_intensive_work(fn ->
        large_data_transformation(huge_dataset)
      end)

      # With explicit result handling
      Foundation.BEAM.Processes.isolate_memory_intensive_work(
        fn -> process_large_file(file_path) end,
        self()
      )
  """
  @spec isolate_memory_intensive_work(function()) :: {:ok, pid()} | {:error, Error.t()}
  def isolate_memory_intensive_work(work_fn) do
    isolate_memory_intensive_work(work_fn, self())
  end

  @spec isolate_memory_intensive_work(function(), pid()) :: {:ok, pid()} | {:error, Error.t()}
  def isolate_memory_intensive_work(work_fn, caller) when is_pid(caller) do
    context = ErrorContext.new(__MODULE__, :isolate_memory_intensive_work)

    ErrorContext.with_context(context, fn ->
      try do
        {:ok, task_pid} =
          Task.start(fn ->
            try do
              result = work_fn.()
              send(caller, {:work_complete, result})
            rescue
              error ->
                send(caller, {:work_error, error})
            end
          end)

        {:ok, task_pid}
      rescue
        error ->
          {:error,
           Error.new(
             code: 5001,
             error_type: :process_start_failed,
             message: "Failed to start memory intensive work process: #{inspect(error)}",
             severity: :high,
             context: context
           )}
      end
    end)
  end

  @doc """
  Gracefully shutdown an ecosystem.

  Terminates all processes in the ecosystem and waits for cleanup.
  Now uses proper OTP supervision for graceful shutdown.
  """
  @spec shutdown_ecosystem(ecosystem()) :: :ok | {:error, Error.t()}
  def shutdown_ecosystem(ecosystem) do
    context = ErrorContext.new(__MODULE__, :shutdown_ecosystem)

    ErrorContext.with_context(context, fn ->
      if ecosystem.supervisor && Process.alive?(ecosystem.supervisor) do
        # Use the new OTP-based shutdown
        Foundation.BEAM.EcosystemSupervisor.shutdown(ecosystem.supervisor)
      else
        # Fallback to manual shutdown for older ecosystems
        all_pids =
          [ecosystem.coordinator | ecosystem.workers] ++
            if ecosystem.supervisor, do: [ecosystem.supervisor], else: []

        # Signal all processes to shutdown
        for pid <- all_pids, Process.alive?(pid) do
          send(pid, :shutdown)
        end

        # Wait for graceful shutdown with timeout
        deadline = System.monotonic_time(:millisecond) + 500
        wait_for_shutdown(all_pids, deadline)

        # Force kill any remaining processes
        for pid <- all_pids, Process.alive?(pid) do
          Process.exit(pid, :kill)
        end

        # Final wait to ensure processes are truly dead with monitoring
        Task.async_stream(
          all_pids,
          fn pid ->
            if Process.alive?(pid) do
              ref = Process.monitor(pid)

              receive do
                {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
              after
                50 ->
                  Process.demonitor(ref, [:flush])
                  :timeout
              end
            else
              :ok
            end
          end,
          timeout: 100
        )
        |> Stream.run()
      end

      :ok
    end)
  end

  defp wait_for_shutdown(pids, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :timeout
    else
      living_pids = Enum.filter(pids, &Process.alive?/1)

      if Enum.empty?(living_pids) do
        :ok
      else
        Process.send_after(self(), {:check_shutdown, pids, deadline}, 10)

        receive do
          {:check_shutdown, ^pids, ^deadline} ->
            wait_for_shutdown(pids, deadline)
        end
      end
    end
  end

  @doc """
  Get information about a process ecosystem.

  Returns detailed information about an ecosystem including process status,
  memory usage, and health metrics.

  ## Examples

      {:ok, info} = ecosystem_info(ecosystem)
      # Returns: %{
      #   coordinator: %{pid: #PID<...>, status: :running, memory: 2048},
      #   workers: [%{pid: #PID<...>, status: :running, memory: 1024}, ...],
      #   total_processes: 11,
      #   total_memory: 12288
      # }
  """
  @spec ecosystem_info(ecosystem()) :: {:ok, map()} | {:error, Error.t()}
  def ecosystem_info(ecosystem) do
    context = ErrorContext.new(__MODULE__, :ecosystem_info)

    ErrorContext.with_context(context, fn ->
      # Check if coordinator was replaced by supervisor
      current_coordinator = get_current_coordinator(ecosystem)

      coordinator_info = process_info_safe(current_coordinator)

      workers_info =
        ecosystem.workers
        |> Enum.map(&process_info_safe/1)
        |> Enum.filter(fn info -> info.status != :dead end)

      total_memory =
        [coordinator_info | workers_info]
        |> Enum.map(& &1[:memory])
        |> Enum.sum()

      # Count only living processes
      living_processes = length(workers_info) + if coordinator_info.status != :dead, do: 1, else: 0

      info = %{
        coordinator: coordinator_info,
        workers: workers_info,
        total_processes: living_processes,
        total_memory: total_memory,
        topology: ecosystem.topology
      }

      {:ok, info}
    end)
  end

  ## Private Functions

  defp has_proper_genserver_start_link?(module) when is_atom(module) do
    try do
      # Check if module is already loaded or can be loaded
      module_loaded =
        function_exported?(module, :module_info, 0) or
          case Code.ensure_loaded(module) do
            {:module, ^module} -> true
            _ -> false
          end

      if module_loaded do
        # Check for required GenServer functions
        function_exported?(module, :start_link, 1) and
          function_exported?(module, :init, 1)
      else
        # In test environment, try checking if it's a test module with full namespace
        # This is a fallback for test modules that might be defined within test files
        test_module_name = :"Elixir.Foundation.BEAM.ProcessesTest.#{module}"

        if function_exported?(test_module_name, :module_info, 0) do
          function_exported?(test_module_name, :start_link, 1) and
            function_exported?(test_module_name, :init, 1)
        else
          false
        end
      end
    rescue
      _ -> false
    end
  end

  defp has_proper_genserver_start_link?(_), do: false

  defp validate_config(config) do
    with :ok <- validate_config_structure(config),
         :ok <- validate_coordinator_config(config) do
      validate_workers_config(config)
    end
  end

  defp validate_config_structure(config) do
    cond do
      not is_map(config) ->
        {:error, "Configuration must be a map"}

      not Map.has_key?(config, :coordinator) ->
        {:error, "Configuration must include :coordinator"}

      not Map.has_key?(config, :workers) ->
        {:error, "Configuration must include :workers"}

      true ->
        :ok
    end
  end

  defp validate_coordinator_config(config) do
    if is_atom(config.coordinator) do
      :ok
    else
      {:error, "Coordinator must be a module name (atom)"}
    end
  end

  defp validate_workers_config(config) do
    cond do
      not is_tuple(config.workers) or tuple_size(config.workers) != 2 ->
        {:error, "Workers must be a {module, options} tuple"}

      not is_atom(elem(config.workers, 0)) ->
        {:error, "Worker module must be an atom"}

      not is_list(elem(config.workers, 1)) ->
        {:error, "Worker options must be a keyword list"}

      true ->
        :ok
    end
  end

  # All manual process management code removed
  # Now uses only OTP supervision via Foundation.BEAM.EcosystemSupervisor

  defp get_current_coordinator(ecosystem) do
    if ecosystem.supervisor && Process.alive?(ecosystem.supervisor) do
      # Use EcosystemSupervisor API instead of process dictionary
      case Foundation.BEAM.EcosystemSupervisor.get_coordinator(ecosystem.supervisor) do
        {:ok, coordinator_pid} -> coordinator_pid
        {:error, :not_found} -> ecosystem.coordinator
      end
    else
      ecosystem.coordinator
    end
  end

  defp process_info_safe(pid) do
    if Process.alive?(pid) do
      case Process.info(pid, [:status, :memory, :message_queue_len]) do
        [status: status, memory: memory, message_queue_len: queue_len] ->
          %{pid: pid, status: status, memory: memory, message_queue_len: queue_len}

        nil ->
          %{pid: pid, status: :dead, memory: 0, message_queue_len: 0}
      end
    else
      %{pid: pid, status: :dead, memory: 0, message_queue_len: 0}
    end
  end
end
