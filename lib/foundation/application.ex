# lib/foundation/application.ex
defmodule Foundation.Application do
  @moduledoc """
  Enhanced Foundation Application Supervisor with MABEAM support.

  Manages the lifecycle of all Foundation components in a supervised manner with
  enhanced service management, health monitoring, and coordination primitives
  for multi-agent systems.

  The supervision tree is designed to be fault-tolerant and to restart
  components in the correct order if failures occur. Enhanced with service
  dependencies, health monitoring, and graceful degradation capabilities.

  ## Supervision Strategy

  The application uses a carefully designed supervision tree:

  1. **Infrastructure Layer**: Core services that everything depends on
     - ProcessRegistry: Service discovery and registration
     - ServiceRegistry: High-level service management
     - Enhanced error handling and telemetry

  2. **Foundation Services Layer**: Core Foundation functionality
     - ConfigServer: Configuration management with hot-reloading
     - EventStore: Event persistence and querying
     - TelemetryService: Metrics and monitoring

  3. **Coordination Layer**: Distributed coordination primitives
     - Coordination.Primitives: Low-level coordination algorithms
     - Infrastructure protection: Rate limiting, circuit breakers, connection pooling

  4. **Application Layer**: Higher-level services
     - TaskSupervisor: Dynamic task management
     - Optional test support services
     - Optional development tools (Tidewave)

  ## Service Dependencies

  Services declare their dependencies and the application ensures proper
  startup order and handles dependency failures gracefully.

  ## Health Monitoring

  All services implement standardized health checking with automatic
  restart policies and degradation strategies.
  """
  use Application
  require Logger

  alias Foundation.ProcessRegistry

  @type startup_phase :: :infrastructure | :foundation_services | :coordination | :application
  @type service_config :: %{
          module: module(),
          args: keyword(),
          dependencies: [atom()],
          startup_phase: startup_phase(),
          health_check_interval: pos_integer(),
          restart_strategy: :permanent | :temporary | :transient
        }

  # Enhanced service definitions with dependencies and health monitoring
  @service_definitions %{
    # Infrastructure Phase - Critical foundation services
    process_registry: %{
      module: ProcessRegistry,
      args: [],
      dependencies: [],
      startup_phase: :infrastructure,
      health_check_interval: 60_000,
      restart_strategy: :permanent
    },

    # Note: ServiceRegistry is a utility module, not a GenServer - no supervision needed

    # Foundation Services Phase - Core business logic
    config_server: %{
      module: Foundation.Services.ConfigServer,
      args: [namespace: :production],
      dependencies: [:process_registry],
      startup_phase: :foundation_services,
      health_check_interval: 30_000,
      restart_strategy: :permanent
    },
    event_store: %{
      module: Foundation.Services.EventStore,
      args: [namespace: :production],
      dependencies: [:process_registry],
      startup_phase: :foundation_services,
      health_check_interval: 30_000,
      restart_strategy: :permanent
    },
    telemetry_service: %{
      module: Foundation.Services.TelemetryService,
      args: [namespace: :production],
      dependencies: [:process_registry],
      startup_phase: :foundation_services,
      health_check_interval: 30_000,
      restart_strategy: :permanent
    },

    # Coordination Phase - Distributed coordination primitives
    # Note: Coordination.Primitives is a utility module, not a GenServer - no supervision needed

    connection_manager: %{
      module: Foundation.Infrastructure.ConnectionManager,
      args: [],
      dependencies: [:telemetry_service],
      startup_phase: :coordination,
      health_check_interval: 45_000,
      restart_strategy: :permanent
    },
    rate_limiter_backend: %{
      module: Foundation.Infrastructure.RateLimiter.HammerBackend,
      args: [],
      dependencies: [],
      startup_phase: :coordination,
      health_check_interval: 120_000,
      restart_strategy: :permanent
    },

    # Application Phase - Higher-level services
    task_supervisor: %{
      module: Task.Supervisor,
      args: [name: Foundation.TaskSupervisor],
      dependencies: [:telemetry_service],
      startup_phase: :application,
      health_check_interval: 60_000,
      restart_strategy: :permanent
    }
  }

  @impl true
  def start(_type, _args) do
    test_mode = Application.get_env(:foundation, :test_mode, false)

    unless test_mode do
      Logger.info("Starting enhanced Foundation application...")
    end

    # Initialize application-level configuration
    setup_application_config()

    # Initialize infrastructure components
    case initialize_infrastructure() do
      :ok ->
        unless test_mode do
          Logger.info("Infrastructure initialization complete")
        end

      {:error, reason} ->
        Logger.error("Infrastructure initialization failed: #{inspect(reason)}")
        {:error, {:infrastructure_init_failed, reason}}
    end

    # Build supervision tree with proper ordering
    children = build_supervision_tree()

    # Enhanced supervisor options with better restart strategies
    opts = [
      strategy: :one_for_one,
      name: Foundation.Supervisor,
      max_restarts: 10,
      max_seconds: 60
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        post_startup_tasks()

        unless test_mode do
          Logger.info("Enhanced Foundation application started successfully")
        end

        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Enhanced Foundation application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping Enhanced Foundation application...")

    # Graceful shutdown sequence
    perform_graceful_shutdown()

    Logger.info("Enhanced Foundation application stopped")
    :ok
  end

  @doc """
  Get the current status of all Foundation services.

  Returns detailed health and dependency information for monitoring.
  """
  @spec get_application_status() :: %{
          status: :healthy | :degraded | :unhealthy,
          services: %{atom() => service_status()},
          startup_phases: %{startup_phase() => phase_status()},
          dependencies: %{atom() => [atom()]},
          health_summary: health_summary()
        }
  def get_application_status do
    service_statuses = get_all_service_statuses()
    phase_statuses = group_services_by_phase(service_statuses)
    overall_status = determine_overall_status(service_statuses)

    %{
      status: overall_status,
      services: service_statuses,
      startup_phases: phase_statuses,
      dependencies: get_dependency_map(),
      health_summary: calculate_health_summary(service_statuses)
    }
  end

  @doc """
  Restart a specific service with dependency checking.

  Ensures dependencies are available before restarting the service.
  """
  @spec restart_service(atom()) :: :ok | {:error, term()}
  def restart_service(service_name) do
    case Map.get(@service_definitions, service_name) do
      nil ->
        {:error, {:unknown_service, service_name}}

      service_config ->
        Logger.info("Restarting service: #{service_name}")

        # Check dependencies first
        case check_service_dependencies(service_config.dependencies) do
          :ok ->
            # Perform restart
            case Supervisor.restart_child(Foundation.Supervisor, service_name) do
              {:ok, _pid} ->
                Logger.info("Service #{service_name} restarted successfully")
                :ok

              {:ok, _pid, _info} ->
                Logger.info("Service #{service_name} restarted successfully")
                :ok

              {:error, reason} ->
                Logger.error("Failed to restart service #{service_name}: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, missing_deps} ->
            Logger.error(
              "Cannot restart #{service_name}: missing dependencies #{inspect(missing_deps)}"
            )

            {:error, {:missing_dependencies, missing_deps}}
        end
    end
  end

  @doc """
  Perform health check on all services.

  Returns detailed health information for monitoring and alerting.
  """
  @spec health_check() :: %{
          overall_health: :healthy | :degraded | :unhealthy,
          service_health: %{atom() => health_status()},
          failed_services: [atom()],
          degraded_services: [atom()],
          recommendations: [String.t()]
        }
  def health_check do
    service_health = perform_health_checks()

    failed_services =
      service_health
      |> Enum.filter(fn {_service, status} -> status.health == :unhealthy end)
      |> Enum.map(fn {service, _status} -> service end)

    degraded_services =
      service_health
      |> Enum.filter(fn {_service, status} -> status.health == :degraded end)
      |> Enum.map(fn {service, _status} -> service end)

    overall_health =
      cond do
        length(failed_services) > 0 -> :unhealthy
        length(degraded_services) > 0 -> :degraded
        true -> :healthy
      end

    recommendations = generate_health_recommendations(failed_services, degraded_services)

    %{
      overall_health: overall_health,
      service_health: service_health,
      failed_services: failed_services,
      degraded_services: degraded_services,
      recommendations: recommendations
    }
  end

  ## Private Functions

  defp setup_application_config do
    # Initialize enhanced error handling
    case Application.get_env(:foundation, :enhanced_error_handling, true) do
      true ->
        # Configure enhanced error types and distributed error handling
        :ok

      false ->
        Logger.info("Enhanced error handling disabled")
    end

    # Setup coordination primitives configuration
    coordination_config = %{
      consensus_timeout: 5000,
      election_timeout: 3000,
      lock_timeout: 5000,
      barrier_timeout: 10_000
    }

    Application.put_env(:foundation, :coordination, coordination_config)

    # Setup service health monitoring
    health_config = %{
      global_health_check_interval: 30_000,
      health_check_timeout: 5000,
      unhealthy_threshold: 3,
      degraded_threshold: 1
    }

    Application.put_env(:foundation, :health_monitoring, health_config)
  end

  defp initialize_infrastructure do
    try do
      # Initialize Hammer configuration for rate limiting
      case Application.get_env(:hammer, :backend) do
        nil ->
          Application.put_env(:hammer, :backend, {Hammer.Backend.ETS,
           [
             # 2 hours
             expiry_ms: 60_000 * 60 * 2,
             # 10 minutes
             cleanup_interval_ms: 60_000 * 10
           ]})

        _ ->
          :ok
      end

      # Ensure Fuse application is started for circuit breakers
      case Application.ensure_all_started(:fuse) do
        {:ok, _apps} -> :ok
        {:error, reason} -> raise "Failed to start Fuse application: #{inspect(reason)}"
      end

      # Initialize coordination primitives infrastructure
      Foundation.Coordination.Primitives.initialize_infrastructure()

      :ok
    rescue
      exception ->
        {:error, {:infrastructure_init_exception, exception}}
    end
  end

  defp build_supervision_tree do
    # Build children in dependency order
    infrastructure_children = build_phase_children(:infrastructure)
    foundation_children = build_phase_children(:foundation_services)
    coordination_children = build_phase_children(:coordination)
    application_children = build_phase_children(:application)

    # Add test and development children
    test_children =
      if Application.get_env(:foundation, :test_mode, false) do
        [child_spec_for_service(:test_supervisor)]
      else
        []
      end

    tidewave_children =
      if should_start_tidewave?() do
        [Foundation.TidewaveEndpoint]
      else
        []
      end

    # Combine all children in startup order
    infrastructure_children ++
      foundation_children ++
      coordination_children ++
      application_children ++
      test_children ++
      tidewave_children
  end

  defp build_phase_children(phase) do
    @service_definitions
    |> Enum.filter(fn {_name, config} -> config.startup_phase == phase end)
    |> Enum.map(fn {service_name, _config} -> child_spec_for_service(service_name) end)
  end

  defp child_spec_for_service(service_name) do
    case Map.get(@service_definitions, service_name) do
      nil ->
        # Handle special cases not in definitions
        case service_name do
          :test_supervisor ->
            {Foundation.TestSupport.TestSupervisor, []}

          _ ->
            raise "Unknown service: #{service_name}"
        end

      service_config ->
        %{
          id: service_name,
          start: {service_config.module, :start_link, [service_config.args]},
          restart: service_config.restart_strategy,
          shutdown: 10_000,
          type: :worker
        }
    end
  end

  defp should_start_tidewave? do
    # Only start Tidewave in development environment if it's loaded
    Application.get_env(:foundation, :environment, :prod) == :dev and Code.ensure_loaded?(Tidewave)
  end

  defp post_startup_tasks do
    test_mode = Application.get_env(:foundation, :test_mode, false)

    unless test_mode do
      # Register application-level health checks
      spawn(fn ->
        # Allow services to fully start
        Process.sleep(1000)
        schedule_periodic_health_check()
      end)

      # Initialize service monitoring
      spawn(fn ->
        # Allow all services to be ready
        Process.sleep(2000)
        initialize_service_monitoring()
      end)
    end

    # Emit application started event
    try do
      Foundation.Events.new_event(:application_started, %{
        timestamp: DateTime.utc_now(),
        services: Map.keys(@service_definitions),
        enhanced_features: [:coordination_primitives, :enhanced_error_handling, :service_monitoring]
      })
      |> Foundation.Events.store()
    rescue
      # Don't fail startup due to event emission
      _ -> :ok
    end
  end

  defp perform_graceful_shutdown do
    Logger.info("Beginning graceful shutdown sequence...")

    # Stop services in reverse dependency order
    shutdown_phases = [:application, :coordination, :foundation_services, :infrastructure]

    Enum.each(shutdown_phases, fn phase ->
      Logger.info("Shutting down #{phase} services...")
      shutdown_phase_services(phase)
    end)

    # Final cleanup
    cleanup_application_resources()
  end

  defp shutdown_phase_services(phase) do
    phase_services =
      @service_definitions
      |> Enum.filter(fn {_name, config} -> config.startup_phase == phase end)
      |> Enum.map(fn {service_name, _config} -> service_name end)

    # Send graceful shutdown signal to each service
    Enum.each(phase_services, fn service_name ->
      case ProcessRegistry.lookup(:production, service_name) do
        {:ok, pid} ->
          Logger.debug("Sending graceful shutdown to #{service_name}")
          send(pid, :shutdown)

        :error ->
          Logger.debug("Service #{service_name} not found during shutdown")
      end
    end)

    # Wait for graceful shutdown
    Process.sleep(1000)
  end

  defp cleanup_application_resources do
    # Clean up ETS tables, close files, etc.
    Logger.debug("Cleaning up application resources...")

    # Cleanup coordination primitive resources
    try do
      Foundation.Coordination.Primitives.cleanup_infrastructure()
    rescue
      _ -> :ok
    end
  end

  defp get_all_service_statuses do
    Enum.reduce(@service_definitions, %{}, fn {service_name, _config}, acc ->
      status = get_service_status(service_name)
      Map.put(acc, service_name, status)
    end)
  end

  defp get_service_status(service_name) do
    case ProcessRegistry.lookup(:production, service_name) do
      {:ok, pid} ->
        %{
          status: :running,
          pid: pid,
          uptime: get_process_uptime(pid),
          memory_usage: get_process_memory(pid),
          message_queue_length: get_message_queue_length(pid),
          health: :healthy,
          last_health_check: DateTime.utc_now()
        }

      :error ->
        %{
          status: :stopped,
          pid: nil,
          uptime: 0,
          memory_usage: 0,
          message_queue_length: 0,
          health: :unhealthy,
          last_health_check: DateTime.utc_now()
        }
    end
  end

  defp group_services_by_phase(service_statuses) do
    phases = [:infrastructure, :foundation_services, :coordination, :application]

    Enum.reduce(phases, %{}, fn phase, acc ->
      phase_services =
        @service_definitions
        |> Enum.filter(fn {_name, config} -> config.startup_phase == phase end)
        |> Enum.map(fn {service_name, _config} -> service_name end)

      phase_status = %{
        services: phase_services,
        healthy_count: count_healthy_services(phase_services, service_statuses),
        total_count: length(phase_services),
        status: determine_phase_status(phase_services, service_statuses)
      }

      Map.put(acc, phase, phase_status)
    end)
  end

  defp determine_overall_status(service_statuses) do
    health_counts =
      service_statuses
      |> Map.values()
      |> Enum.group_by(& &1.health)
      |> Enum.map(fn {health, services} -> {health, length(services)} end)
      |> Enum.into(%{})

    unhealthy_count = Map.get(health_counts, :unhealthy, 0)
    degraded_count = Map.get(health_counts, :degraded, 0)

    cond do
      unhealthy_count > 0 -> :unhealthy
      degraded_count > 0 -> :degraded
      true -> :healthy
    end
  end

  defp get_dependency_map do
    Enum.reduce(@service_definitions, %{}, fn {service_name, config}, acc ->
      Map.put(acc, service_name, config.dependencies)
    end)
  end

  defp calculate_health_summary(service_statuses) do
    total_services = map_size(service_statuses)

    health_counts =
      service_statuses
      |> Map.values()
      |> Enum.group_by(& &1.health)
      |> Enum.map(fn {health, services} -> {health, length(services)} end)
      |> Enum.into(%{})

    %{
      total_services: total_services,
      healthy: Map.get(health_counts, :healthy, 0),
      degraded: Map.get(health_counts, :degraded, 0),
      unhealthy: Map.get(health_counts, :unhealthy, 0),
      health_percentage: calculate_health_percentage(health_counts, total_services)
    }
  end

  defp calculate_health_percentage(health_counts, total_services) do
    if total_services == 0 do
      0.0
    else
      healthy_count = Map.get(health_counts, :healthy, 0)
      degraded_count = Map.get(health_counts, :degraded, 0)

      # Degraded services count as 50% healthy
      weighted_healthy = healthy_count + degraded_count * 0.5
      Float.round(weighted_healthy / total_services * 100, 1)
    end
  end

  defp check_service_dependencies(dependencies) do
    missing_deps =
      dependencies
      |> Enum.filter(fn dep_service ->
        case dep_service do
          :process_registry ->
            # Special case: check if ProcessRegistry itself is running
            Process.whereis(ProcessRegistry) == nil

          _ ->
            # Normal case: look up through ProcessRegistry
            case ProcessRegistry.lookup(:production, dep_service) do
              {:ok, _pid} -> false
              :error -> true
            end
        end
      end)

    if Enum.empty?(missing_deps) do
      :ok
    else
      {:error, missing_deps}
    end
  end

  defp count_healthy_services(service_names, service_statuses) do
    service_names
    |> Enum.map(fn name -> Map.get(service_statuses, name, %{health: :unhealthy}) end)
    |> Enum.count(fn status -> status.health == :healthy end)
  end

  defp determine_phase_status(service_names, service_statuses) do
    phase_services =
      Enum.map(service_names, fn name ->
        Map.get(service_statuses, name, %{health: :unhealthy})
      end)

    unhealthy_count = Enum.count(phase_services, fn s -> s.health == :unhealthy end)
    degraded_count = Enum.count(phase_services, fn s -> s.health == :degraded end)

    cond do
      unhealthy_count > 0 -> :unhealthy
      degraded_count > 0 -> :degraded
      true -> :healthy
    end
  end

  defp perform_health_checks do
    Enum.reduce(@service_definitions, %{}, fn {service_name, config}, acc ->
      health_status = perform_service_health_check(service_name, config)
      Map.put(acc, service_name, health_status)
    end)
  end

  defp perform_service_health_check(service_name, _config) do
    # Special handling for services that don't support health checks
    case service_name do
      :process_registry ->
        # ProcessRegistry is the Registry itself, check if it's alive
        case Process.whereis(ProcessRegistry) do
          nil ->
            %{
              health: :unhealthy,
              response_time: nil,
              last_check: DateTime.utc_now(),
              details: "ProcessRegistry not found"
            }

          pid when is_pid(pid) ->
            %{
              health: :healthy,
              response_time: 0,
              last_check: DateTime.utc_now(),
              details: "ProcessRegistry running"
            }
        end

      :task_supervisor ->
        # TaskSupervisor is a built-in supervisor, check if it's alive
        case Process.whereis(Foundation.TaskSupervisor) do
          nil ->
            %{
              health: :unhealthy,
              response_time: nil,
              last_check: DateTime.utc_now(),
              details: "TaskSupervisor not found"
            }

          pid when is_pid(pid) ->
            %{
              health: :healthy,
              response_time: 0,
              last_check: DateTime.utc_now(),
              details: "TaskSupervisor running"
            }
        end

      _ ->
        # For other services, try the normal health check
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            try do
              # Attempt to get health status from service if it supports it
              case GenServer.call(pid, :health_status, 5000) do
                {:ok, health} ->
                  %{
                    health: health,
                    response_time: measure_response_time(pid),
                    last_check: DateTime.utc_now(),
                    details: "Health check successful"
                  }

                {:error, reason} ->
                  %{
                    health: :degraded,
                    response_time: nil,
                    last_check: DateTime.utc_now(),
                    details: "Health check returned error: #{inspect(reason)}"
                  }

                other ->
                  %{
                    health: :degraded,
                    response_time: nil,
                    last_check: DateTime.utc_now(),
                    details: "Unexpected health check response: #{inspect(other)}"
                  }
              end
            catch
              :exit, {:timeout, _} ->
                %{
                  health: :degraded,
                  response_time: nil,
                  last_check: DateTime.utc_now(),
                  details: "Health check timed out"
                }

              :exit, {reason, _} ->
                # Service doesn't support health_status, but it's alive - that's ok
                if is_tuple(reason) and elem(reason, 0) == :function_clause do
                  %{
                    health: :healthy,
                    response_time: nil,
                    last_check: DateTime.utc_now(),
                    details: "Service alive but doesn't support health checks"
                  }
                else
                  %{
                    health: :unhealthy,
                    response_time: nil,
                    last_check: DateTime.utc_now(),
                    details: "Health check failed: #{inspect(reason)}"
                  }
                end
            end

          :error ->
            %{
              health: :unhealthy,
              response_time: nil,
              last_check: DateTime.utc_now(),
              details: "Service process not found"
            }
        end
    end
  end

  defp measure_response_time(pid) do
    start_time = System.monotonic_time(:microsecond)

    try do
      GenServer.call(pid, :ping, 1000)
      end_time = System.monotonic_time(:microsecond)
      end_time - start_time
    catch
      _, _ -> nil
    end
  end

  defp generate_health_recommendations(failed_services, degraded_services) do
    recommendations = []

    recommendations =
      if length(failed_services) > 0 do
        failed_recommendations = [
          "Immediate attention required: #{length(failed_services)} services are unhealthy",
          "Check logs for failed services: #{Enum.join(failed_services, ", ")}",
          "Consider restarting failed services if logs indicate transient issues"
        ]

        recommendations ++ failed_recommendations
      else
        recommendations
      end

    recommendations =
      if length(degraded_services) > 0 do
        degraded_recommendations = [
          "Monitor degraded services: #{Enum.join(degraded_services, ", ")}",
          "Check resource utilization and dependencies for degraded services",
          "Consider scaling or optimizing degraded services"
        ]

        recommendations ++ degraded_recommendations
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["All services are healthy"]
    else
      recommendations
    end
  end

  defp schedule_periodic_health_check do
    health_config = Application.get_env(:foundation, :health_monitoring, %{})
    interval = Map.get(health_config, :global_health_check_interval, 30_000)

    Process.send_after(self(), :perform_health_check, interval)
  end

  defp initialize_service_monitoring do
    Logger.info("Initializing service monitoring...")

    # Start periodic health checking
    spawn(fn ->
      health_check_loop()
    end)

    # Initialize service dependency monitoring
    spawn(fn ->
      dependency_monitor_loop()
    end)
  end

  defp health_check_loop do
    health_config = Application.get_env(:foundation, :health_monitoring, %{})
    interval = Map.get(health_config, :global_health_check_interval, 30_000)

    try do
      health_result = health_check()

      # Emit health metrics
      Foundation.Telemetry.emit_gauge(
        [:foundation, :application, :health_percentage],
        health_result.overall_health |> health_to_percentage(),
        %{
          failed_services: length(health_result.failed_services),
          degraded_services: length(health_result.degraded_services)
        }
      )

      # Log health issues
      if health_result.overall_health != :healthy do
        Logger.warning("Application health: #{health_result.overall_health}")
        Logger.warning("Failed services: #{inspect(health_result.failed_services)}")
        Logger.warning("Degraded services: #{inspect(health_result.degraded_services)}")
      end
    rescue
      error ->
        Logger.error("Health check failed: #{inspect(error)}")
    end

    Process.sleep(interval)
    health_check_loop()
  end

  defp dependency_monitor_loop do
    try do
      # Check for services with unmet dependencies
      unmet_dependencies = find_unmet_dependencies()

      if not Enum.empty?(unmet_dependencies) do
        Logger.warning("Services with unmet dependencies: #{inspect(unmet_dependencies)}")

        # Emit dependency warning
        Foundation.Telemetry.emit_counter(
          [:foundation, :application, :dependency_warnings],
          %{unmet_count: length(unmet_dependencies)}
        )
      end
    rescue
      error ->
        Logger.error("Dependency monitoring failed: #{inspect(error)}")
    end

    # Check every minute
    Process.sleep(60_000)
    dependency_monitor_loop()
  end

  defp find_unmet_dependencies do
    Enum.flat_map(@service_definitions, fn {service_name, config} ->
      case check_service_dependencies(config.dependencies) do
        :ok -> []
        {:error, missing_deps} -> [{service_name, missing_deps}]
      end
    end)
  end

  defp health_to_percentage(:healthy), do: 100.0
  defp health_to_percentage(:degraded), do: 50.0
  defp health_to_percentage(:unhealthy), do: 0.0

  defp get_process_uptime(pid) do
    case Process.info(pid, :reductions) do
      {_, _} ->
        # Rough estimate - in production, you'd track actual start time
        System.monotonic_time(:millisecond)

      nil ->
        0
    end
  end

  defp get_process_memory(pid) do
    case Process.info(pid, :memory) do
      {:memory, memory} -> memory
      nil -> 0
    end
  end

  defp get_message_queue_length(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, length} -> length
      nil -> 0
    end
  end

  # Type definitions for better documentation
  @type service_status :: %{
          status: :running | :stopped,
          pid: pid() | nil,
          uptime: non_neg_integer(),
          memory_usage: non_neg_integer(),
          message_queue_length: non_neg_integer(),
          health: :healthy | :degraded | :unhealthy,
          last_health_check: DateTime.t()
        }

  @type phase_status :: %{
          services: [atom()],
          healthy_count: non_neg_integer(),
          total_count: non_neg_integer(),
          status: :healthy | :degraded | :unhealthy
        }

  @type health_summary :: %{
          total_services: non_neg_integer(),
          healthy: non_neg_integer(),
          degraded: non_neg_integer(),
          unhealthy: non_neg_integer(),
          health_percentage: float()
        }

  @type health_status :: %{
          health: :healthy | :degraded | :unhealthy,
          response_time: non_neg_integer() | nil,
          last_check: DateTime.t(),
          details: String.t()
        }
end
