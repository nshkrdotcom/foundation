defmodule Foundation.Application do
  @moduledoc """
  Clean Foundation Application Supervisor - Pure BEAM Infrastructure.

  Manages core infrastructure services with zero application-specific knowledge.
  Designed for distribution-ready deployment and agent-aware capabilities.

  ## Supervision Strategy

  1. **Infrastructure**: Core process registry and coordination primitives
  2. **Foundation Services**: Configuration, events, telemetry
  3. **Coordination**: Distributed coordination mechanisms
  4. **Application**: Task supervision and optional development tools

  All services are agent-aware but application-agnostic.
  """

  use Application
  require Logger

  @type startup_phase :: :infrastructure | :foundation_services | :coordination | :application

  @type service_config :: %{
          module: module(),
          args: keyword(),
          dependencies: [atom()],
          startup_phase: startup_phase(),
          health_check_interval: pos_integer(),
          restart_strategy: :permanent | :temporary | :transient
        }

  # Clean service definitions - no application-specific services
  @service_definitions %{
    # Infrastructure Phase - Critical foundation services
    process_registry: %{
      module: Foundation.ProcessRegistry,
      args: [],
      dependencies: [],
      startup_phase: :infrastructure,
      health_check_interval: 60_000,
      restart_strategy: :permanent
    },

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
    coordination_service: %{
      module: Foundation.Coordination.Service,
      args: [],
      dependencies: [:process_registry, :telemetry_service],
      startup_phase: :coordination,
      health_check_interval: 45_000,
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
      Logger.info("Starting clean Foundation infrastructure...")
    end

    # Initialize application configuration
    setup_application_config()

    # Initialize infrastructure components
    case initialize_infrastructure() do
      :ok ->
        unless test_mode do
          Logger.info("Foundation infrastructure initialized")
        end

      {:error, reason} ->
        Logger.error("Foundation infrastructure initialization failed: #{inspect(reason)}")
        {:error, {:infrastructure_init_failed, reason}}
    end

    # Build clean supervision tree
    children = build_supervision_tree()

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
          Logger.info("Foundation infrastructure started successfully")
        end

        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Foundation infrastructure: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping Foundation infrastructure...")
    perform_graceful_shutdown()
    Logger.info("Foundation infrastructure stopped")
    :ok
  end

  @doc """
  Get the current status of all Foundation services.
  """
  @spec get_application_status() :: %{
          status: :healthy | :degraded | :unhealthy,
          services: %{atom() => service_status()},
          startup_phases: %{startup_phase() => phase_status()},
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
      health_summary: calculate_health_summary(service_statuses)
    }
  end

  ## Private Functions

  defp setup_application_config do
    # Enhanced error handling configuration
    case Application.get_env(:foundation, :enhanced_error_handling, true) do
      true -> :ok
      false -> Logger.info("Enhanced error handling disabled")
    end

    # Coordination primitives configuration
    coordination_config = %{
      consensus_timeout: 5000,
      election_timeout: 3000,
      lock_timeout: 5000,
      barrier_timeout: 10_000
    }
    Application.put_env(:foundation, :coordination, coordination_config)

    # Service health monitoring configuration
    health_config = %{
      global_health_check_interval: 30_000,
      health_check_timeout: 5000,
      unhealthy_threshold: 3,
      degraded_threshold: 1
    }
    Application.put_env(:foundation, :health_monitoring, health_config)
  end

  defp initialize_infrastructure do
    # Initialize coordination primitives infrastructure
    Foundation.Coordination.Primitives.initialize_infrastructure()

    # Initialize ProcessRegistry optimizations
    Foundation.ProcessRegistry.initialize_optimizations()

    :ok
  rescue
    exception ->
      {:error, {:infrastructure_init_exception, exception}}
  end

  defp build_supervision_tree do
    # Build children in clean dependency order
    infrastructure_children = build_phase_children(:infrastructure)
    foundation_children = build_phase_children(:foundation_services)
    coordination_children = build_phase_children(:coordination)
    application_children = build_phase_children(:application)

    # Add optional development tools
    optional_children = build_optional_children()

    # Clean supervision tree - no application-specific services
    infrastructure_children ++
      foundation_children ++
      coordination_children ++
      application_children ++
      optional_children
  end

  defp build_phase_children(phase) do
    @service_definitions
    |> Enum.filter(fn {_name, config} -> config.startup_phase == phase end)
    |> Enum.map(fn {service_name, _config} -> child_spec_for_service(service_name) end)
  end

  defp child_spec_for_service(service_name) do
    case Map.get(@service_definitions, service_name) do
      nil ->
        raise "Unknown service: #{service_name}"

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

  defp build_optional_children do
    optional = []

    # Add test support if in test mode
    optional = if Application.get_env(:foundation, :test_mode, false) do
      [{Foundation.TestSupport.TestSupervisor, []} | optional]
    else
      optional
    end

    # Add development tools if available and in dev environment
    optional = if should_start_dev_tools?() do
      [Foundation.DevTools.Endpoint | optional]
    else
      optional
    end

    optional
  end

  defp should_start_dev_tools? do
    Application.get_env(:foundation, :environment, :prod) == :dev and
    Code.ensure_loaded?(Foundation.DevTools.Endpoint)
  end

  defp post_startup_tasks do
    test_mode = Application.get_env(:foundation, :test_mode, false)

    unless test_mode do
      # Start health monitoring
      spawn(fn -> start_health_monitoring() end)

      # Emit application started event
      emit_startup_event()
    end
  end

  defp perform_graceful_shutdown do
    Logger.info("Beginning graceful Foundation shutdown...")

    # Shutdown in reverse dependency order
    shutdown_phases = [:application, :coordination, :foundation_services, :infrastructure]

    Enum.each(shutdown_phases, fn phase ->
      Logger.debug("Shutting down #{phase} services...")
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

    Enum.each(phase_services, fn service_name ->
      case Foundation.ProcessRegistry.lookup(:production, service_name) do
        {:ok, pid} ->
          Logger.debug("Graceful shutdown signal to #{service_name}")
          send(pid, :shutdown)
        :error ->
          Logger.debug("Service #{service_name} not found during shutdown")
      end
    end)
  end

  defp cleanup_application_resources do
    Logger.debug("Cleaning up Foundation resources...")

    # Cleanup coordination primitives
    try do
      Foundation.Coordination.Primitives.cleanup_infrastructure()
    rescue
      _ -> :ok
    end

    # Cleanup ProcessRegistry optimizations
    try do
      Foundation.ProcessRegistry.cleanup_optimizations()
    rescue
      _ -> :ok
    end
  end

  defp emit_startup_event do
    try do
      Foundation.Events.new_event(:foundation_started, %{
        timestamp: DateTime.utc_now(),
        services: Map.keys(@service_definitions),
        features: [:agent_aware_infrastructure, :coordination_primitives, :enhanced_observability]
      })
      |> Foundation.Events.store()
    rescue
      _ -> :ok
    end
  end

  defp start_health_monitoring do
    health_config = Application.get_env(:foundation, :health_monitoring, %{})
    interval = Map.get(health_config, :global_health_check_interval, 30_000)

    health_check_loop(interval)
  end

  defp health_check_loop(interval) do
    try do
      health_result = perform_comprehensive_health_check()

      # Emit health metrics
      Foundation.Telemetry.emit_gauge(
        [:foundation, :health_percentage],
        health_to_percentage(health_result.overall_health),
        %{service_count: map_size(health_result.services)}
      )

      # Log health issues in non-test environments
      unless Application.get_env(:foundation, :environment) == :test do
        if health_result.overall_health != :healthy do
          Logger.warning("Foundation health: #{health_result.overall_health}")
        end
      end
    rescue
      error ->
        Logger.error("Health check failed: #{inspect(error)}")
    end

    Process.send_after(self(), :health_check, interval)

    receive do
      :health_check -> health_check_loop(interval)
    end
  end

  defp perform_comprehensive_health_check do
    service_statuses = get_all_service_statuses()
    overall_status = determine_overall_status(service_statuses)

    %{
      overall_health: overall_status,
      services: service_statuses,
      timestamp: DateTime.utc_now()
    }
  end

  defp get_all_service_statuses do
    Enum.reduce(@service_definitions, %{}, fn {service_name, _config}, acc ->
      status = get_service_status(service_name)
      Map.put(acc, service_name, status)
    end)
  end

  defp get_service_status(service_name) do
    case Foundation.ProcessRegistry.lookup(:production, service_name) do
      {:ok, pid} ->
        %{
          status: :running,
          pid: pid,
          health: :healthy,
          last_check: DateTime.utc_now()
        }

      :error ->
        %{
          status: :stopped,
          pid: nil,
          health: :unhealthy,
          last_check: DateTime.utc_now()
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
      unhealthy: Map.get(health_counts, :unhealthy, 0)
    }
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

  defp health_to_percentage(:healthy), do: 100.0
  defp health_to_percentage(:degraded), do: 50.0
  defp health_to_percentage(:unhealthy), do: 0.0

  # Type definitions
  @type service_status :: %{
          status: :running | :stopped,
          pid: pid() | nil,
          health: :healthy | :degraded | :unhealthy,
          last_check: DateTime.t()
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
          unhealthy: non_neg_integer()
        }
end