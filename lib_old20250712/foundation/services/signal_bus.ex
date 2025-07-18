defmodule Foundation.Services.SignalBus do
  @moduledoc """
  Foundation service wrapper for Jido.Signal.Bus.

  Provides proper service lifecycle management for the signal bus within
  the Foundation service architecture. Handles startup, health checks,
  and graceful shutdown of the signal bus.

  ## Configuration

  The signal bus can be configured in your application config:

      config :foundation, :signal_bus,
        name: :foundation_signal_bus,
        middleware: [
          {Jido.Signal.Bus.Middleware.Logger, []}
        ]

  ## Service Health

  The service provides health checks to ensure the signal bus is operational
  and can handle signal publishing and subscription operations.
  """

  use GenServer
  require Logger
  alias Foundation.Telemetry

  @type start_option ::
          {:name, atom()}
          | {:middleware, list()}
          | {atom(), term()}

  # --- Public API ---

  @doc """
  Starts the Signal Bus service.

  ## Options

  - `:name` - Name for the signal bus (default: :foundation_signal_bus)
  - `:middleware` - List of middleware modules (default: Logger middleware)
  - Other options are passed through to Jido.Signal.Bus
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the health status of the signal bus service.

  Returns `:healthy` if the bus is running and operational,
  `:degraded` if there are issues, or `:unhealthy` if the bus is down.
  """
  @spec health_check(atom()) :: :healthy | :unhealthy
  def health_check(name \\ __MODULE__) do
    case GenServer.call(name, :health_check, 1000) do
      :healthy -> :healthy
      _ -> :unhealthy
    end
  catch
    :exit, _ -> :unhealthy
  end

  @doc """
  Gets the signal bus process identifier for direct use with Jido.Signal.Bus APIs.
  """
  @spec get_bus_name(atom()) :: atom() | {:error, :not_started}
  def get_bus_name(name \\ __MODULE__) do
    try do
      GenServer.call(name, :get_bus_name, 1000)
    catch
      :exit, _ -> {:error, :not_started}
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    # Get configuration from app config and merge with provided opts
    config = Application.get_env(:foundation, :signal_bus, [])
    merged_opts = Keyword.merge(config, opts)

    bus_name = Keyword.get(merged_opts, :name, :foundation_signal_bus)

    middleware =
      Keyword.get(merged_opts, :middleware, [
        {Jido.Signal.Bus.Middleware.Logger, []}
      ])

    # Prepare options for Jido.Signal.Bus
    bus_opts =
      [
        name: bus_name,
        middleware: middleware
      ] ++ Keyword.drop(merged_opts, [:name, :middleware])

    Logger.info("Starting Foundation Signal Bus service: #{inspect(bus_name)}")

    # Check if Jido.Signal.Registry is available
    case Process.whereis(Jido.Signal.Registry) do
      nil ->
        Logger.warning("Jido.Signal.Registry not available - SignalBus will run in degraded mode")

        state = %{
          bus_name: bus_name,
          bus_pid: nil,
          started_at: System.monotonic_time(:millisecond),
          degraded_mode: true
        }

        Telemetry.service_started(__MODULE__, %{
          bus_name: bus_name,
          middleware_count: 0,
          degraded_mode: true
        })

        {:ok, state}

      _pid ->
        case Jido.Signal.Bus.start_link(bus_opts) do
          {:ok, bus_pid} ->
            Logger.info("Foundation Signal Bus started successfully: #{inspect(bus_name)}")

            state = %{
              bus_name: bus_name,
              bus_pid: bus_pid,
              started_at: System.monotonic_time(:millisecond),
              degraded_mode: false
            }

            Telemetry.service_started(__MODULE__, %{
              bus_name: bus_name,
              middleware_count: length(middleware),
              degraded_mode: false
            })

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to start Foundation Signal Bus: #{inspect(reason)}")
            {:stop, reason}
        end
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    start_time = System.monotonic_time()

    health_status =
      cond do
        Map.get(state, :degraded_mode, false) ->
          :degraded

        state.bus_pid && Process.alive?(state.bus_pid) ->
          # Try a simple operation to verify the bus is responsive
          case Jido.Signal.Bus.whereis(state.bus_name) do
            {:ok, _pid} -> :healthy
            {:error, _} -> :degraded
          end

        true ->
          :unhealthy
      end

    Telemetry.emit(
      [:foundation, :signal_bus, :health_check],
      %{
        duration: System.monotonic_time() - start_time,
        timestamp: System.system_time()
      },
      %{
        bus_name: state.bus_name,
        status: health_status
      }
    )

    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_bus_name, _from, state) do
    {:reply, state.bus_name, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{bus_pid: pid} = state) do
    Logger.error("Foundation Signal Bus process died: #{inspect(reason)}")

    Telemetry.service_error(__MODULE__, {:signal_bus_died, reason}, %{
      bus_name: state.bus_name,
      operation: :monitor
    })

    {:stop, {:signal_bus_died, reason}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Foundation Signal Bus service received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Foundation Signal Bus service shutting down: #{inspect(reason)}")

    uptime = System.monotonic_time(:millisecond) - state.started_at

    Telemetry.service_stopped(__MODULE__, %{
      bus_name: state.bus_name,
      reason: reason,
      uptime_ms: uptime
    })

    if Process.alive?(state.bus_pid) do
      # Give the bus a chance to shut down gracefully
      Process.exit(state.bus_pid, :shutdown)
    end

    :ok
  end
end
