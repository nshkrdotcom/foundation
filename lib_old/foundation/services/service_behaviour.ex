# lib/foundation/services/service_behaviour.ex
defmodule Foundation.Services.ServiceBehaviour do
  @moduledoc """
  Standardized service behavior for Foundation services with enhanced lifecycle management.

  Provides consistent service registration, health checking, and lifecycle management
  patterns that integrate seamlessly with Foundation's infrastructure and prepare
  for MABEAM multi-agent coordination.

  ## Features
  - Automatic service registration with ProcessRegistry
  - Standardized health checking with customizable intervals
  - Graceful shutdown with configurable timeouts
  - Telemetry integration for service metrics
  - Configuration hot-reloading support
  - Resource usage monitoring
  - Service dependency management

  ## Usage

      defmodule MyService do
        use Foundation.Services.ServiceBehaviour

        # Implement required callbacks
        @impl true
        def service_config, do: %{health_check_interval: 30_000}

        @impl true
        def handle_health_check(state), do: {:ok, :healthy, state}
      end

  ## Required Callbacks

  Services using this behavior must implement:
  - `service_config/0` - Return service configuration
  - `handle_health_check/1` - Perform health check and return status

  ## Optional Callbacks

  - `handle_dependency_ready/2` - Called when a dependency becomes available
  - `handle_dependency_lost/2` - Called when a dependency becomes unavailable
  - `handle_config_change/2` - Called when configuration changes
  """

  alias Foundation.{Events, ProcessRegistry, ServiceRegistry, Telemetry}
  # Note: Error alias removed as it's not used in this module

  @type service_state :: %{
          service_name: atom(),
          config: map(),
          health_status: health_status(),
          last_health_check: DateTime.t() | nil,
          startup_time: DateTime.t(),
          dependencies: [atom()],
          dependency_status: %{atom() => boolean()},
          metrics: service_metrics(),
          namespace: ProcessRegistry.namespace()
        }

  @type health_status :: :starting | :healthy | :degraded | :unhealthy | :stopping
  @type service_metrics :: %{
          health_checks: non_neg_integer(),
          health_check_failures: non_neg_integer(),
          uptime_ms: non_neg_integer(),
          memory_usage: non_neg_integer(),
          message_queue_length: non_neg_integer()
        }

  @type service_config :: %{
          required(:health_check_interval) => pos_integer(),
          required(:graceful_shutdown_timeout) => pos_integer(),
          required(:dependencies) => [atom()],
          required(:telemetry_enabled) => boolean(),
          required(:resource_monitoring) => boolean(),
          optional(atom()) => term()
        }

  @doc """
  Return the service configuration.

  ## Returns
  Map containing service configuration including:
  - `health_check_interval` - Milliseconds between health checks
  - `graceful_shutdown_timeout` - Maximum time for graceful shutdown
  - `dependencies` - List of required service dependencies
  - `telemetry_enabled` - Whether to emit telemetry events
  - `resource_monitoring` - Whether to monitor resource usage
  """
  @callback service_config() :: service_config()

  @doc """
  Perform a health check on the service.

  ## Parameters
  - `state` - Current GenServer state

  ## Returns
  - `{:ok, :healthy, new_state}` - Service is healthy
  - `{:ok, :degraded, new_state}` - Service is degraded but operational
  - `{:ok, :unhealthy, new_state}` - Service is unhealthy
  - `{:ok, status, new_state, details}` - Enhanced health check with details
  - `{:error, reason, new_state}` - Health check failed
  """
  @callback handle_health_check(term()) ::
              {:ok, :healthy | :degraded | :unhealthy, term()}
              | {:ok, :healthy | :degraded | :unhealthy, term(), map()}
              | {:error, term(), term()}

  @doc """
  Called when a dependency becomes available.

  ## Parameters
  - `dependency` - The dependency service that became available
  - `state` - Current GenServer state

  ## Returns
  - `{:ok, new_state}` - Dependency ready handled successfully

  Note: Default implementation always returns `{:ok, state}`. Override to handle errors.
  """
  @callback handle_dependency_ready(atom(), term()) :: {:ok, term()}

  @doc """
  Called when a dependency becomes unavailable.

  ## Parameters
  - `dependency` - The dependency service that became unavailable
  - `state` - Current GenServer state

  ## Returns
  - `{:ok, new_state}` - Dependency loss handled successfully

  Note: Default implementation always returns `{:ok, state}`. Override to handle errors.
  """
  @callback handle_dependency_lost(atom(), term()) :: {:ok, term()}

  @doc """
  Called when service configuration changes.

  ## Parameters
  - `new_config` - The new configuration
  - `state` - Current GenServer state

  ## Returns
  - `{:ok, new_state}` - Configuration change handled successfully

  Note: Default implementation always returns `{:ok, state}`. Override to handle errors.
  """
  @callback handle_config_change(map(), term()) :: {:ok, term()}

  # Optional callbacks with default implementations
  @optional_callbacks [
    handle_dependency_ready: 2,
    handle_dependency_lost: 2,
    handle_config_change: 2
  ]

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Foundation.Services.ServiceBehaviour
      use GenServer

      # Import enhanced service functionality
      import Foundation.Services.ServiceBehaviour

      # Default service configuration
      @default_service_config %{
        health_check_interval: 30_000,
        graceful_shutdown_timeout: 10_000,
        dependencies: [],
        telemetry_enabled: true,
        resource_monitoring: true
      }

      unquote(genserver_callbacks())
      unquote(service_helpers())
    end
  end

  defp genserver_callbacks do
    quote do
      # Enhanced GenServer callbacks with service behavior
      @impl GenServer
      def init(opts) do
        Foundation.Services.ServiceBehaviour.init_service_state(
          __MODULE__,
          opts,
          @default_service_config
        )
      end

      @impl GenServer
      def handle_info(:health_check, state) do
        new_state = __service_perform_health_check(state)
        __service_schedule_health_check(state.config.health_check_interval)
        {:noreply, new_state}
      end

      @impl GenServer
      def handle_info({:dependency_status, dependency, status}, state) do
        new_dependency_status = Map.put(state.dependency_status, dependency, status)
        new_state = %{state | dependency_status: new_dependency_status}

        if status do
          {:ok, updated_state} = handle_dependency_ready(dependency, new_state)
          {:noreply, updated_state}
        else
          {:ok, updated_state} = handle_dependency_lost(dependency, new_state)
          {:noreply, updated_state}
        end
      end

      @impl GenServer
      def handle_info(:shutdown, state) do
        # Graceful shutdown
        __service_emit_event(:stopping, state)
        {:stop, :shutdown, state}
      end

      @impl GenServer
      def handle_call(:health_status, _from, state) do
        {:reply, {:ok, state.health_status}, state}
      end

      @impl GenServer
      def handle_call(:service_metrics, _from, state) do
        metrics = __service_calculate_current_metrics(state)
        {:reply, {:ok, metrics}, state}
      end

      @impl GenServer
      def handle_call({:update_config, new_config}, _from, state) do
        {:ok, new_state} = handle_config_change(new_config, state)
        updated_state = %{new_state | config: Map.merge(state.config, new_config)}
        {:reply, :ok, updated_state}
      end

      @impl GenServer
      def terminate(reason, state) do
        __service_emit_event(:stopped, state, %{reason: reason})

        # Call user-defined termination if exists
        if function_exported?(__MODULE__, :terminate_service, 2) do
          apply(__MODULE__, :terminate_service, [reason, state])
        end

        :ok
      end

      # Default implementations for optional callbacks
      def handle_dependency_ready(_dependency, state), do: {:ok, state}
      def handle_dependency_lost(_dependency, state), do: {:ok, state}
      def handle_config_change(_new_config, state), do: {:ok, state}

      # User must implement init_service/1 instead of init/1
      def init_service(_opts), do: {:ok, %{}}

      defoverridable handle_dependency_ready: 2,
                     handle_dependency_lost: 2,
                     handle_config_change: 2,
                     init_service: 1
    end
  end

  defp service_helpers do
    quote do
      # Helper functions available to services
      defp __service_emit_event(event_type, state, extra_metadata \\ %{}) do
        Foundation.Services.ServiceBehaviour.emit_service_event(event_type, state, extra_metadata)
      end

      defp __service_perform_health_check(state) do
        Foundation.Services.ServiceBehaviour.perform_health_check(__MODULE__, state)
      end

      defp __service_schedule_health_check(interval) do
        Foundation.Services.ServiceBehaviour.schedule_health_check(interval)
      end

      defp __service_check_dependencies(state) do
        Foundation.Services.ServiceBehaviour.check_dependencies(state)
      end

      defp __service_initialize_metrics do
        Foundation.Services.ServiceBehaviour.initialize_metrics()
      end

      defp __service_calculate_current_metrics(state) do
        Foundation.Services.ServiceBehaviour.calculate_current_metrics(state)
      end

      defp __service_update_health_metrics(metrics, result) do
        Foundation.Services.ServiceBehaviour.update_health_metrics(metrics, result)
      end

      defp __service_emit_health_check_success(state, start_time) do
        Foundation.Services.ServiceBehaviour.emit_health_check_success(state, start_time)
      end

      defp __service_emit_health_check_degraded(state, start_time) do
        Foundation.Services.ServiceBehaviour.emit_health_check_degraded(state, start_time)
      end

      defp __service_emit_health_check_failure(state, reason, start_time) do
        Foundation.Services.ServiceBehaviour.emit_health_check_failure(state, reason, start_time)
      end
    end
  end

  # Public helper functions that can be called from the using modules
  def init_service_state(module, opts, default_config) do
    service_name = module
    namespace = Keyword.get(opts, :namespace, :production)
    config = Map.merge(default_config, apply(module, :service_config, []))

    # Initialize service state
    service_state = %{
      service_name: service_name,
      config: config,
      health_status: :starting,
      last_health_check: nil,
      startup_time: DateTime.utc_now(),
      dependencies: config.dependencies,
      dependency_status: %{},
      metrics: Foundation.Services.ServiceBehaviour.initialize_metrics(),
      namespace: namespace
    }

    # Merge with any user-defined state
    user_state =
      case apply(module, :init_service, [opts]) do
        {:ok, state} -> state
        {:ok, state, _timeout} -> state
        state -> state
      end

    final_state = Map.merge(service_state, user_state)

    # Register with service registry
    case ServiceRegistry.register(namespace, service_name, self()) do
      :ok ->
        # Start health checking
        if config.health_check_interval > 0 do
          Foundation.Services.ServiceBehaviour.schedule_health_check(config.health_check_interval)
        end

        # Check dependencies
        Foundation.Services.ServiceBehaviour.check_dependencies(final_state)

        # Emit service started event
        Foundation.Services.ServiceBehaviour.emit_service_event(:started, final_state)

        {:ok, final_state}

      {:error, reason} ->
        {:stop, {:service_registration_failed, reason}}
    end
  end

  def emit_service_event(event_type, state, extra_metadata \\ %{}) do
    if state.config.telemetry_enabled do
      metadata =
        Map.merge(
          %{
            service: state.service_name,
            health_status: state.health_status,
            namespace: state.namespace
          },
          extra_metadata
        )

      Telemetry.emit_counter([:foundation, :service, event_type], metadata)

      # Also emit as structured event
      Events.new_event(:"service_#{event_type}", metadata)
      |> Events.store()
    end
  end

  def perform_health_check(module, state) do
    start_time = System.monotonic_time()

    try do
      case apply(module, :handle_health_check, [state]) do
        {:ok, :healthy, new_state} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_success(state, start_time)

          %{
            new_state
            | health_status: :healthy,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :success)
          }

        {:ok, :degraded, new_state} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_degraded(state, start_time)

          %{
            new_state
            | health_status: :degraded,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :degraded)
          }

        {:ok, :unhealthy, new_state} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_failure(
            state,
            :unhealthy,
            start_time
          )

          %{
            new_state
            | health_status: :unhealthy,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :failure)
          }

        {:ok, :healthy, new_state, _details} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_success(state, start_time)

          %{
            new_state
            | health_status: :healthy,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :success)
          }

        {:ok, :degraded, new_state, _details} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_degraded(state, start_time)

          %{
            new_state
            | health_status: :degraded,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :degraded)
          }

        {:ok, :unhealthy, new_state, _details} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_failure(
            state,
            :unhealthy,
            start_time
          )

          %{
            new_state
            | health_status: :unhealthy,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :failure)
          }

        {:error, reason, new_state} ->
          Foundation.Services.ServiceBehaviour.emit_health_check_failure(state, reason, start_time)

          %{
            new_state
            | health_status: :unhealthy,
              last_health_check: DateTime.utc_now(),
              metrics:
                Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :failure)
          }
      end
    rescue
      error ->
        Foundation.Services.ServiceBehaviour.emit_health_check_failure(state, error, start_time)

        %{
          state
          | health_status: :unhealthy,
            last_health_check: DateTime.utc_now(),
            metrics:
              Foundation.Services.ServiceBehaviour.update_health_metrics(state.metrics, :failure)
        }
    end
  end

  def schedule_health_check(interval) when interval > 0 do
    Process.send_after(self(), :health_check, interval)
  end

  def check_dependencies(state) when is_map(state) do
    if length(state.dependencies) > 0 do
      Enum.each(state.dependencies, fn dependency ->
        # For pragmatic implementation, assume dependencies are healthy if they're registered
        is_healthy =
          case ServiceRegistry.lookup(state.namespace, dependency) do
            {:ok, _pid} -> true
            {:error, _} -> false
          end

        send(self(), {:dependency_status, dependency, is_healthy})
      end)
    end
  end

  def initialize_metrics do
    %{
      health_checks: 0,
      health_check_failures: 0,
      uptime_ms: 0,
      memory_usage: 0,
      message_queue_length: 0
    }
  end

  def update_health_metrics(metrics, result) do
    new_checks = metrics.health_checks + 1

    new_failures =
      case result do
        :failure -> metrics.health_check_failures + 1
        _ -> metrics.health_check_failures
      end

    %{metrics | health_checks: new_checks, health_check_failures: new_failures}
  end

  def calculate_current_metrics(state) do
    uptime_ms = DateTime.diff(DateTime.utc_now(), state.startup_time, :millisecond)

    process_info = Process.info(self(), [:memory, :message_queue_len])
    memory_usage = Keyword.get(process_info, :memory, 0)
    message_queue_length = Keyword.get(process_info, :message_queue_len, 0)

    %{
      state.metrics
      | uptime_ms: uptime_ms,
        memory_usage: memory_usage,
        message_queue_length: message_queue_length
    }
  end

  def emit_health_check_success(state, start_time) do
    duration = System.monotonic_time() - start_time

    if state.config.telemetry_enabled do
      Telemetry.emit_histogram(
        [:foundation, :service, :health_check, :duration],
        duration,
        %{service: state.service_name, result: :success}
      )
    end
  end

  def emit_health_check_degraded(state, start_time) do
    duration = System.monotonic_time() - start_time

    if state.config.telemetry_enabled do
      Telemetry.emit_histogram(
        [:foundation, :service, :health_check, :duration],
        duration,
        %{service: state.service_name, result: :degraded}
      )
    end
  end

  def emit_health_check_failure(state, reason, start_time) do
    duration = System.monotonic_time() - start_time

    if state.config.telemetry_enabled do
      Telemetry.emit_histogram(
        [:foundation, :service, :health_check, :duration],
        duration,
        %{service: state.service_name, result: :failure}
      )

      Telemetry.emit_counter(
        [:foundation, :service, :health_check, :failures],
        %{service: state.service_name, reason: inspect(reason)}
      )
    end
  end
end
