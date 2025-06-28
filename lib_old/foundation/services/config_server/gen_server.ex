defmodule Foundation.Services.ConfigServer.GenServer do
  @moduledoc """
  Internal GenServer implementation for configuration management.

  This is the actual GenServer implementation that handles configuration
  persistence, updates, and notifications. It delegates business logic
  to ConfigLogic module.

  This module is now internal to the ConfigServer proxy and should not
  be called directly. Use Foundation.Services.ConfigServer instead.

  See `@type server_state` for the internal state structure.
  """

  use GenServer
  require Logger

  alias Foundation.{ProcessRegistry, ServiceRegistry}
  alias Foundation.Logic.ConfigLogic
  alias Foundation.Services.{EventStore, TelemetryService}
  alias Foundation.Types.Config
  alias Foundation.Validation.ConfigValidator

  @typedoc "Internal state of the configuration server"
  @type server_state :: %{
          config: Config.t(),
          subscribers: [pid()],
          monitors: %{reference() => pid()},
          metrics: metrics(),
          namespace: ProcessRegistry.namespace()
        }

  @typedoc "Metrics tracking for the configuration server"
  @type metrics :: %{
          start_time: integer(),
          updates_count: non_neg_integer(),
          last_update: integer() | nil
        }

  ## GenServer API

  @doc """
  Start the configuration server.

  ## Parameters
  - `opts`: Keyword list of options passed to GenServer initialization
    - `:namespace` - The namespace to register in (defaults to :production)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :production)
    name = ServiceRegistry.via_tuple(namespace, :config_server)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :namespace, namespace), name: name)
  end

  @doc """
  Stop the configuration server.
  """
  @spec stop() :: :ok
  def stop do
    case ServiceRegistry.lookup(:production, :config_server) do
      {:ok, pid} -> GenServer.stop(pid)
      {:error, _} -> :ok
    end
  end

  ## GenServer Callbacks

  @doc """
  Initialize the GenServer state.

  Builds the initial configuration and sets up metrics tracking.
  """
  @impl GenServer
  @spec init(keyword()) :: {:ok, server_state()} | {:stop, term()}
  def init(opts) do
    namespace = Keyword.get(opts, :namespace, :production)

    case ConfigLogic.build_config(opts) do
      {:ok, config} ->
        unless Application.get_env(:foundation, :test_mode, false) do
          Logger.info(
            "Configuration server initialized successfully in namespace #{inspect(namespace)}"
          )
        end

        state = %{
          config: config,
          subscribers: [],
          monitors: %{},
          namespace: namespace,
          metrics: %{
            start_time: System.monotonic_time(:millisecond),
            updates_count: 0,
            last_update: nil
          }
        }

        {:ok, state}

      {:error, error} ->
        Logger.error("Failed to initialize configuration: #{inspect(error)}")
        {:stop, {:config_validation_failed, error}}
    end
  end

  @impl GenServer
  @spec handle_call(term(), GenServer.from(), server_state()) ::
          {:reply, term(), server_state()} | {:noreply, server_state()}
  def handle_call(:get_config, _from, %{config: config} = state) do
    {:reply, {:ok, config}, state}
  end

  @impl GenServer
  def handle_call({:get_config_path, path}, _from, %{config: config} = state) do
    result = ConfigLogic.get_config_value(config, path)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:update_config, path, value}, _from, %{config: config} = state) do
    case ConfigLogic.update_config(config, path, value) do
      {:ok, new_config} ->
        new_state = %{
          state
          | config: new_config,
            metrics:
              Map.merge(state.metrics, %{
                updates_count: state.metrics.updates_count + 1,
                last_update: System.monotonic_time(:millisecond)
              })
        }

        # Notify subscribers
        notify_subscribers(state.subscribers, {:config_updated, path, value})

        # Emit event to EventStore for audit and correlation
        emit_config_event(:config_updated, %{
          path: path,
          new_value: value,
          previous_value: ConfigLogic.get_config_value(config, path),
          timestamp: System.monotonic_time(:millisecond)
        })

        # Emit telemetry for config updates
        emit_config_telemetry(:config_updated, %{path: path})

        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:reset_config, _from, state) do
    new_config = ConfigLogic.reset_config()

    case ConfigValidator.validate(new_config) do
      :ok ->
        new_state = %{state | config: new_config}
        notify_subscribers(state.subscribers, {:config_reset, new_config})

        # Emit event to EventStore for audit and correlation
        emit_config_event(:config_reset, %{
          timestamp: System.monotonic_time(:millisecond),
          reset_from_updates_count: state.metrics.updates_count
        })

        # Emit telemetry for config resets
        emit_config_telemetry(:config_reset, %{
          reset_from_updates_count: state.metrics.updates_count
        })

        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, %{subscribers: subscribers, monitors: monitors} = state) do
    if pid in subscribers do
      {:reply, :ok, state}
    else
      # Fix race condition: add to list first, then monitor
      new_subscribers = [pid | subscribers]
      monitor_ref = Process.monitor(pid)
      new_monitors = Map.put(monitors, monitor_ref, pid)

      new_state = %{state | subscribers: new_subscribers, monitors: new_monitors}
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(
        {:unsubscribe, pid},
        _from,
        %{subscribers: subscribers, monitors: monitors} = state
      ) do
    new_subscribers = List.delete(subscribers, pid)

    # Find and demonitor the reference for this PID
    {new_monitors, _} =
      Enum.reduce(monitors, {%{}, nil}, fn
        {ref, ^pid}, {acc_monitors, _} ->
          Process.demonitor(ref, [:flush])
          {acc_monitors, ref}

        {ref, other_pid}, {acc_monitors, found_ref} ->
          {Map.put(acc_monitors, ref, other_pid), found_ref}
      end)

    new_state = %{state | subscribers: new_subscribers, monitors: new_monitors}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:reset_state, _from, state) do
    # Reset to initial state (for testing)
    case ConfigLogic.build_config([]) do
      {:ok, config} ->
        new_state = %{
          config: config,
          subscribers: [],
          monitors: %{},
          metrics: %{
            start_time: System.monotonic_time(:millisecond),
            updates_count: 0,
            last_update: nil
          }
        }

        {:reply, :ok, new_state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, %{metrics: metrics, subscribers: subscribers} = state) do
    current_time = System.monotonic_time(:millisecond)

    status = %{
      status: :running,
      uptime_ms: current_time - metrics.start_time,
      updates_count: metrics.updates_count,
      last_update: metrics.last_update,
      subscribers_count: length(subscribers)
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:health_status, _from, state) do
    # Health check for application monitoring
    {:reply, {:ok, :healthy}, state}
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    # Simple ping for response time measurement
    {:reply, :pong, state}
  end

  @impl GenServer
  def handle_call(request, _from, state) do
    Logger.warning("Unauthorized or invalid request to ConfigServer: #{inspect(request)}")
    {:reply, {:error, :unauthorized_access}, state}
  end

  @impl GenServer
  @spec handle_info(term(), server_state()) :: {:noreply, server_state()}
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %{subscribers: subscribers, monitors: monitors} = state
      ) do
    # Remove dead subscriber using the monitor reference
    new_subscribers = List.delete(subscribers, pid)
    new_monitors = Map.delete(monitors, ref)
    new_state = %{state | subscribers: new_subscribers, monitors: new_monitors}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in ConfigServer: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  @spec notify_subscribers([pid()], term()) :: :ok
  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:config_notification, message})
    end)
  end

  @spec emit_config_event(atom(), map()) :: :ok
  defp emit_config_event(event_type, data) do
    # Only emit if EventStore is available to avoid blocking config operations
    if EventStore.available?() do
      try do
        case Foundation.Events.new_event(event_type, data) do
          {:ok, event} ->
            case EventStore.store(event) do
              {:ok, _id} ->
                :ok

              {:error, error} ->
                Logger.warning("Failed to emit config event: #{inspect(error)}")
            end

          {:error, error} ->
            Logger.warning("Failed to create config event: #{inspect(error)}")
        end
      rescue
        error ->
          Logger.warning("Exception while emitting config event: #{inspect(error)}")
      end
    end
  end

  @spec emit_config_telemetry(atom(), map()) :: :ok
  defp emit_config_telemetry(operation_type, metadata) do
    # Only emit if TelemetryService is available to avoid blocking config operations
    if TelemetryService.available?() do
      try do
        case operation_type do
          :config_updated ->
            TelemetryService.emit_counter([:foundation, :config_updates], metadata)

          :config_reset ->
            TelemetryService.emit_counter([:foundation, :config_resets], metadata)
        end
      rescue
        error ->
          Logger.warning("Exception while emitting config telemetry: #{inspect(error)}")
      end
    end
  end
end
