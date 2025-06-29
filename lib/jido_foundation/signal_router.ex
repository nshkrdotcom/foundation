defmodule JidoFoundation.SignalRouter do
  @moduledoc """
  Signal routing system for Jido agents through Foundation telemetry.

  This module provides a production-ready signal routing system that:
  - Listens to all Jido signal telemetry events
  - Routes signals to subscribed handlers based on signal types
  - Supports wildcard pattern matching for signal types
  - Provides telemetry metrics for routing performance
  - Handles handler failures gracefully

  ## Usage

      # Start the signal router
      {:ok, router_pid} = JidoFoundation.SignalRouter.start_link()

      # Subscribe to specific signal types
      :ok = JidoFoundation.SignalRouter.subscribe("task.completed", handler_pid)

      # Subscribe to wildcard patterns
      :ok = JidoFoundation.SignalRouter.subscribe("error.*", error_handler_pid)

      # Emit signals (usually done by agents)
      JidoFoundation.Bridge.emit_signal(agent_pid, signal)

  ## Signal Format

  Signals should be maps with the following structure:

      %{
        id: unique_identifier,
        type: "signal.type",
        source: "agent://agent_identifier",
        data: %{...},
        time: DateTime.utc_now(),
        metadata: %{...}
      }

  ## Wildcard Patterns

  The router supports simple wildcard patterns using '*' at the end:

  - "error.*" matches "error.validation", "error.timeout", etc.
  - "task.*" matches "task.started", "task.completed", etc.
  - Exact matches always work: "task.completed" matches only "task.completed"
  """

  use GenServer
  require Logger

  defstruct [:subscriptions, :telemetry_attached, :telemetry_handler_id]

  ## Client API

  @doc """
  Starts the signal router.

  ## Options

  - `:name` - Process name (default: `__MODULE__`)
  - `:attach_telemetry` - Whether to attach telemetry handlers (default: true)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes a handler process to receive signals of a specific type.

  ## Examples

      # Subscribe to exact signal type
      :ok = subscribe("task.completed", handler_pid)

      # Subscribe to wildcard pattern
      :ok = subscribe("error.*", error_handler_pid)
  """
  def subscribe(signal_type, handler_pid, router \\ __MODULE__) do
    GenServer.call(router, {:subscribe, signal_type, handler_pid})
  end

  @doc """
  Unsubscribes a handler from receiving signals of a specific type.
  """
  def unsubscribe(signal_type, handler_pid, router \\ __MODULE__) do
    GenServer.call(router, {:unsubscribe, signal_type, handler_pid})
  end

  @doc """
  Gets all current signal subscriptions.
  """
  def get_subscriptions(router \\ __MODULE__) do
    GenServer.call(router, :get_subscriptions)
  end

  @doc """
  Gets statistics about the router's performance.
  """
  def get_stats(router \\ __MODULE__) do
    GenServer.call(router, :get_stats)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    attach_telemetry = Keyword.get(opts, :attach_telemetry, true)
    # Create unique handler ID for this router instance
    handler_id = "jido-signal-router-#{:erlang.unique_integer([:positive])}"

    state = %__MODULE__{
      subscriptions: %{},
      telemetry_attached: false,
      telemetry_handler_id: handler_id
    }

    state =
      if attach_telemetry do
        attach_telemetry_handlers(handler_id, self())
        %{state | telemetry_attached: true}
      else
        state
      end

    Logger.info("JidoFoundation.SignalRouter started")
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, signal_type, handler_pid}, _from, state) do
    # Monitor the handler so we can clean up if it dies
    Process.monitor(handler_pid)

    current_handlers = Map.get(state.subscriptions, signal_type, [])
    new_handlers = [handler_pid | current_handlers] |> Enum.uniq()
    new_subscriptions = Map.put(state.subscriptions, signal_type, new_handlers)

    Logger.debug("Subscribed #{inspect(handler_pid)} to signal type '#{signal_type}'")

    # Emit telemetry for subscription
    :telemetry.execute(
      [:jido, :signal_router, :subscription],
      %{handlers_count: length(new_handlers)},
      %{signal_type: signal_type, handler_pid: handler_pid, operation: :subscribe}
    )

    {:reply, :ok, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def handle_call({:unsubscribe, signal_type, handler_pid}, _from, state) do
    current_handlers = Map.get(state.subscriptions, signal_type, [])
    new_handlers = List.delete(current_handlers, handler_pid)
    new_subscriptions = Map.put(state.subscriptions, signal_type, new_handlers)

    Logger.debug("Unsubscribed #{inspect(handler_pid)} from signal type '#{signal_type}'")

    # Emit telemetry for unsubscription
    :telemetry.execute(
      [:jido, :signal_router, :subscription],
      %{handlers_count: length(new_handlers)},
      %{signal_type: signal_type, handler_pid: handler_pid, operation: :unsubscribe}
    )

    {:reply, :ok, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def handle_call(:get_subscriptions, _from, state) do
    {:reply, state.subscriptions, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_subscription_patterns: map_size(state.subscriptions),
      total_handlers: state.subscriptions |> Map.values() |> List.flatten() |> length(),
      subscription_patterns: Map.keys(state.subscriptions),
      telemetry_attached: state.telemetry_attached
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:route_signal, event, measurements, metadata}, _from, state) do
    case event do
      [:jido, :signal, :emitted] ->
        signal_type = metadata[:signal_type]

        if signal_type do
          route_signal_to_handlers(signal_type, measurements, metadata, state.subscriptions)
        end

      _ ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:route_signal, event, measurements, metadata}, state) do
    # Keep cast handler for backward compatibility, but route to call handler
    case handle_call({:route_signal, event, measurements, metadata}, nil, state) do
      {:reply, :ok, new_state} -> {:noreply, new_state}
      _other -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, dead_pid, _reason}, state) do
    # Clean up subscriptions for dead processes
    new_subscriptions =
      state.subscriptions
      |> Enum.map(fn {signal_type, handlers} ->
        {signal_type, List.delete(handlers, dead_pid)}
      end)
      |> Enum.reject(fn {_signal_type, handlers} -> Enum.empty?(handlers) end)
      |> Enum.into(%{})

    Logger.debug("Cleaned up subscriptions for dead process #{inspect(dead_pid)}")

    {:noreply, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def terminate(reason, state) do
    if state.telemetry_attached do
      detach_telemetry_handlers(state.telemetry_handler_id)
    end

    Logger.info("JidoFoundation.SignalRouter terminating: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp attach_telemetry_handlers(handler_id, router_pid) do
    :telemetry.attach_many(
      handler_id,
      [
        # Only listen to emitted signals, not routed to prevent recursion
        [:jido, :signal, :emitted]
      ],
      fn event, measurements, metadata, _config ->
        # Use synchronous call for deterministic routing behavior in tests
        # This ensures telemetry events are emitted in the correct order
        try do
          GenServer.call(router_pid, {:route_signal, event, measurements, metadata}, 5000)
        catch
          # Router not running
          :exit, {:noproc, _} -> :ok
          # Timeout, continue
          :exit, {:timeout, _} -> :ok
          # Prevent recursive calls
          :exit, {:calling_self, _} -> :ok
        end
      end,
      %{}
    )
  end

  defp detach_telemetry_handlers(handler_id) do
    :telemetry.detach(handler_id)
  end

  defp route_signal_to_handlers(signal_type, measurements, metadata, subscriptions) do
    start_time = System.monotonic_time()

    # Find all matching handlers (exact match + wildcard patterns)
    matching_handlers =
      subscriptions
      |> Enum.flat_map(fn {pattern, handlers} ->
        if matches_pattern?(signal_type, pattern) do
          handlers
        else
          []
        end
      end)
      |> Enum.uniq()

    # Route signal to all matching handlers with error protection
    successful_deliveries =
      matching_handlers
      |> Enum.map(fn handler_pid ->
        try do
          send(handler_pid, {:routed_signal, signal_type, measurements, metadata})
          :ok
        catch
          kind, reason ->
            Logger.warning(
              "Failed to route signal to handler #{inspect(handler_pid)}: #{kind} #{inspect(reason)}"
            )

            :error
        end
      end)
      |> Enum.count(&(&1 == :ok))

    # Calculate routing time
    routing_time = System.monotonic_time() - start_time

    # Emit routing telemetry
    :telemetry.execute(
      [:jido, :signal, :routed],
      %{
        handlers_count: length(matching_handlers),
        successful_deliveries: successful_deliveries,
        routing_time_microseconds: System.convert_time_unit(routing_time, :native, :microsecond)
      },
      %{
        signal_type: signal_type,
        handlers: matching_handlers,
        routing_success_rate:
          if(length(matching_handlers) > 0,
            do: successful_deliveries / length(matching_handlers),
            else: 0.0
          )
      }
    )
  end

  defp matches_pattern?(signal_type, pattern) do
    cond do
      # Exact match
      signal_type == pattern ->
        true

      # Wildcard pattern matching
      String.ends_with?(pattern, "*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(signal_type, prefix)

      # No match
      true ->
        false
    end
  end
end
