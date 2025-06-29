defmodule JidoFoundation.SignalRoutingTest do
  # Using signal routing isolation mode for comprehensive isolation
  use Foundation.UnifiedTestFoundation, :signal_routing

  alias JidoFoundation.Bridge

  # Mock Signal Router that manages signal subscriptions and routing
  defmodule SignalRouter do
    use GenServer

    defstruct [:subscriptions, :handlers, :telemetry_handler_id]

    def start_link(opts \\ []) do
      name = Keyword.get(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def init(opts) do
      # Create unique telemetry handler ID for this router instance
      unique_id = :erlang.unique_integer([:positive])
      handler_id = "jido-signal-router-#{unique_id}"
      
      # Get the router name from the process
      router_name = Keyword.get(opts, :name, __MODULE__)
      
      # Subscribe to all Jido signal telemetry events with unique handler ID
      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :signal, :emitted],
          [:jido, :signal, :routed]
        ],
        fn event, measurements, metadata, config ->
          GenServer.cast(router_name, {:route_signal, event, measurements, metadata, config})
        end,
        %{}
      )

      {:ok, %__MODULE__{subscriptions: %{}, handlers: %{}, telemetry_handler_id: handler_id}}
    end

    def subscribe(router_pid \\ __MODULE__, signal_type, handler_pid) do
      GenServer.call(router_pid, {:subscribe, signal_type, handler_pid})
    end

    def unsubscribe(router_pid \\ __MODULE__, signal_type, handler_pid) do
      GenServer.call(router_pid, {:unsubscribe, signal_type, handler_pid})
    end

    def get_subscriptions(router_pid \\ __MODULE__) do
      GenServer.call(router_pid, :get_subscriptions)
    end

    def handle_call({:subscribe, signal_type, handler_pid}, _from, state) do
      current_handlers = Map.get(state.subscriptions, signal_type, [])
      new_handlers = [handler_pid | current_handlers] |> Enum.uniq()
      new_subscriptions = Map.put(state.subscriptions, signal_type, new_handlers)

      {:reply, :ok, %{state | subscriptions: new_subscriptions}}
    end

    def handle_call({:unsubscribe, signal_type, handler_pid}, _from, state) do
      current_handlers = Map.get(state.subscriptions, signal_type, [])
      new_handlers = List.delete(current_handlers, handler_pid)
      new_subscriptions = Map.put(state.subscriptions, signal_type, new_handlers)

      {:reply, :ok, %{state | subscriptions: new_subscriptions}}
    end

    def handle_call(:get_subscriptions, _from, state) do
      {:reply, state.subscriptions, state}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, {:ok, state}, state}
    end

    def handle_cast({:route_signal, event, measurements, metadata, _config}, state) do
      case event do
        [:jido, :signal, :emitted] ->
          signal_type = metadata[:signal_type]

          # Find all matching handlers (exact match + wildcard patterns)
          all_handlers =
            state.subscriptions
            |> Enum.filter(fn {pattern, _handlers} -> matches_pattern?(signal_type, pattern) end)
            |> Enum.flat_map(fn {_pattern, handlers} -> handlers end)
            |> Enum.uniq()

          # Route signal to all matching handlers
          Enum.each(all_handlers, fn handler_pid ->
            send(handler_pid, {:routed_signal, signal_type, measurements, metadata})
          end)

          # Emit routing telemetry
          measurements = %{handlers_count: length(all_handlers)}
          metadata = %{signal_type: signal_type, handlers: all_handlers}
          :telemetry.execute(
            [:jido, :signal, :routed],
            measurements,
            metadata
          )

        _ ->
          :ok
      end

      {:noreply, state}
    end

    # Helper function to match signal patterns
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

  # Mock Signal Handler that receives routed signals
  defmodule SignalHandler do
    use GenServer

    defstruct [:id, :received_signals]

    def start_link(id) do
      GenServer.start_link(__MODULE__, id)
    end

    def init(id) do
      {:ok, %__MODULE__{id: id, received_signals: []}}
    end

    def get_received_signals(pid) do
      GenServer.call(pid, :get_received_signals)
    end

    def handle_info({:routed_signal, signal_type, measurements, metadata}, state) do
      new_signal = %{
        type: signal_type,
        measurements: measurements,
        metadata: metadata,
        received_at: System.system_time(:microsecond)
      }

      new_signals = [new_signal | state.received_signals]
      {:noreply, %{state | received_signals: new_signals}}
    end

    def handle_call(:get_received_signals, _from, state) do
      {:reply, Enum.reverse(state.received_signals), state}
    end
  end

  describe "Jido.Signal routing through Foundation.Telemetry" do
    test "routes signals to subscribed handlers by type", %{registry: registry, signal_router: router, test_context: ctx} do
      # Create signal handlers
      {:ok, handler1} = SignalHandler.start_link("handler1")
      {:ok, handler2} = SignalHandler.start_link("handler2")
      {:ok, handler3} = SignalHandler.start_link("handler3")

      on_exit(fn ->
        # Clean up subscriptions
        try do
          SignalRouter.unsubscribe(router, "error.validation", handler1)
          SignalRouter.unsubscribe(router, "task.completed", handler2)
          SignalRouter.unsubscribe(router, "error.validation", handler3)
        catch
          # Ignore errors if handlers are already dead
          _, _ -> :ok
        end

        try do
          if Process.alive?(handler1), do: GenServer.stop(handler1)
        catch
          _, _ -> :ok
        end
        
        try do
          if Process.alive?(handler2), do: GenServer.stop(handler2)
        catch
          _, _ -> :ok
        end
        
        try do
          if Process.alive?(handler3), do: GenServer.stop(handler3)
        catch
          _, _ -> :ok
        end
      end)

      # Subscribe handlers to different signal types
      :ok = SignalRouter.subscribe(router, "error.validation", handler1)
      :ok = SignalRouter.subscribe(router, "task.completed", handler2)
      # Multiple handlers for same type
      :ok = SignalRouter.subscribe(router, "error.validation", handler3)

      # Create an agent to emit signals
      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)
      on_exit(fn -> if Process.alive?(agent), do: Process.exit(agent, :normal) end)

      :ok = Bridge.register_agent(agent, capabilities: [:signal_routing], registry: registry)

      # Attach telemetry handler BEFORE emitting signals
      test_pid = self()
      routing_ref = make_ref()
      
      :telemetry.attach(
        "test-routing-completion-#{inspect(routing_ref)}",
        [:jido, :signal, :routed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {routing_ref, :routing_complete, metadata[:signal_type], measurements[:handlers_count]})
        end,
        nil
      )
      
      on_exit(fn ->
        try do
          :telemetry.detach("test-routing-completion-#{inspect(routing_ref)}")
        catch
          _, _ -> :ok
        end
      end)

      # Emit different types of signals (using shared bus for Phase 1 simplicity)
      Bridge.emit_signal(agent, %{
        id: 1,
        type: "error.validation",
        source: "agent://#{inspect(agent)}",
        data: %{field: "email", message: "Invalid format"}
      })

      Bridge.emit_signal(agent, %{
        id: 2,
        type: "task.completed",
        source: "agent://#{inspect(agent)}",
        data: %{task_id: "task_123", result: "success"}
      })

      Bridge.emit_signal(agent, %{
        id: 3,
        type: "info.status",
        source: "agent://#{inspect(agent)}",
        data: %{status: "processing"}
      })
      
      # We expect 3 signals to be routed: error.validation (2 handlers), task.completed (1 handler), info.status (0 handlers)
      assert_receive {^routing_ref, :routing_complete, "error.validation", 2}, 1000
      assert_receive {^routing_ref, :routing_complete, "task.completed", 1}, 1000
      assert_receive {^routing_ref, :routing_complete, "info.status", 0}, 1000

      # Verify handlers received appropriate signals
      handler1_signals = SignalHandler.get_received_signals(handler1)
      handler2_signals = SignalHandler.get_received_signals(handler2)
      handler3_signals = SignalHandler.get_received_signals(handler3)

      # Handler 1 should receive error.validation signal
      assert length(handler1_signals) == 1
      assert hd(handler1_signals).type == "error.validation"

      # Handler 2 should receive task.completed signal
      assert length(handler2_signals) == 1
      assert hd(handler2_signals).type == "task.completed"

      # Handler 3 should also receive error.validation signal
      assert length(handler3_signals) == 1
      assert hd(handler3_signals).type == "error.validation"
    end

    test "supports dynamic subscription management", %{registry: registry, signal_router: router, test_context: ctx} do
      {:ok, handler} = SignalHandler.start_link("dynamic_handler")
      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)

      on_exit(fn ->
        if Process.alive?(handler), do: GenServer.stop(handler)
        if Process.alive?(agent), do: Process.exit(agent, :normal)
      end)

      :ok = Bridge.register_agent(agent, capabilities: [:dynamic_routing], registry: registry)

      # Initially no subscriptions
      assert SignalRouter.get_subscriptions(router) == %{}

      # Subscribe to task signals
      :ok = SignalRouter.subscribe(router, "task.started", handler)
      subscriptions = SignalRouter.get_subscriptions(router)
      assert subscriptions["task.started"] == [handler]

      # Attach telemetry handler BEFORE emitting signals
      test_pid = self()
      routing_ref = make_ref()
      
      :telemetry.attach(
        "test-dynamic-routing-#{inspect(routing_ref)}",
        [:jido, :signal, :routed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {routing_ref, :routing_complete, metadata[:signal_type], measurements[:handlers_count]})
        end,
        nil
      )
      
      on_exit(fn ->
        try do
          :telemetry.detach("test-dynamic-routing-#{inspect(routing_ref)}")
        catch
          _, _ -> :ok
        end
      end)

      # Emit a signal - should be received
      Bridge.emit_signal(agent, %{
        id: 1,
        type: "task.started",
        source: "agent://#{inspect(agent)}",
        data: %{task_id: "task_001"}
      })
      
      # Wait for the task.started signal to be routed to 1 handler
      assert_receive {^routing_ref, :routing_complete, "task.started", 1}, 1000
      
      signals = SignalHandler.get_received_signals(handler)
      assert length(signals) == 1

      # Unsubscribe
      :ok = SignalRouter.unsubscribe(router, "task.started", handler)
      subscriptions = SignalRouter.get_subscriptions(router)
      assert subscriptions["task.started"] == []

      # Emit another signal - should not be received
      Bridge.emit_signal(agent, %{
        id: 2,
        type: "task.started",
        source: "agent://#{inspect(agent)}",
        data: %{task_id: "task_002"}
      })

      # Wait for signal routing completion - should route to 0 handlers since we unsubscribed
      assert_receive {^routing_ref, :routing_complete, "task.started", 0}, 1000
      
      signals = SignalHandler.get_received_signals(handler)
      # Still only the first signal
      assert length(signals) == 1
    end

    test "emits routing telemetry events", %{registry: registry, signal_router: router, test_context: ctx} do
      test_pid = self()

      # Attach telemetry handler for routing events
      :telemetry.attach(
        "test-routing-events",
        [:jido, :signal, :routed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-routing-events")
      end)

      {:ok, handler} = SignalHandler.start_link("telemetry_handler")
      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)

      on_exit(fn ->
        if Process.alive?(handler), do: GenServer.stop(handler)
        if Process.alive?(agent), do: Process.exit(agent, :normal)
      end)

      :ok = Bridge.register_agent(agent, capabilities: [:routing_telemetry], registry: registry)
      :ok = SignalRouter.subscribe(router, "workflow.completed", handler)

      # Emit signal
      Bridge.emit_signal(agent, %{
        id: 1,
        type: "workflow.completed",
        source: "agent://#{inspect(agent)}",
        data: %{workflow_id: "wf_123"}
      })

      # Verify routing telemetry
      assert_receive {:telemetry, [:jido, :signal, :routed], measurements, metadata}
      assert measurements.handlers_count == 1
      assert metadata.signal_type == "workflow.completed"
      assert metadata.handlers == [handler]
    end

    test "handles signal routing errors gracefully", %{registry: registry, signal_router: router, test_context: ctx} do
      # Create a dead handler process
      dead_handler = spawn(fn -> :ok end)
      ref = Process.monitor(dead_handler)
      assert_receive {:DOWN, ^ref, :process, ^dead_handler, _}

      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)
      on_exit(fn -> if Process.alive?(agent), do: Process.exit(agent, :normal) end)

      :ok = Bridge.register_agent(agent, capabilities: [:error_handling], registry: registry)

      # Subscribe the dead handler
      :ok = SignalRouter.subscribe(router, "error.test", dead_handler)

      # Emit signal - should not crash the router
      result =
        Bridge.emit_signal_protected(agent, %{
          id: 1,
          type: "error.test",
          source: "agent://#{inspect(agent)}",
          data: %{test: true}
        })

      assert result == :ok

      # Router should still be alive
      assert Process.alive?(router)
    end

    test "supports wildcard signal subscriptions", %{registry: registry, signal_router: router, test_context: ctx} do
      {:ok, wildcard_handler} = SignalHandler.start_link("wildcard_handler")
      {:ok, specific_handler} = SignalHandler.start_link("specific_handler")
      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)

      on_exit(fn ->
        if Process.alive?(wildcard_handler), do: GenServer.stop(wildcard_handler)
        if Process.alive?(specific_handler), do: GenServer.stop(specific_handler)
        if Process.alive?(agent), do: Process.exit(agent, :normal)
      end)

      :ok = Bridge.register_agent(agent, capabilities: [:wildcard_routing], registry: registry)

      # Subscribe to all error signals (wildcard pattern)
      :ok = SignalRouter.subscribe(router, "error.*", wildcard_handler)
      :ok = SignalRouter.subscribe(router, "error.validation", specific_handler)

      # Attach telemetry handler BEFORE emitting signals
      test_pid = self()
      routing_ref = make_ref()
      
      :telemetry.attach(
        "test-wildcard-routing-#{inspect(routing_ref)}",
        [:jido, :signal, :routed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {routing_ref, :routing_complete, metadata[:signal_type], measurements[:handlers_count]})
        end,
        nil
      )
      
      on_exit(fn ->
        try do
          :telemetry.detach("test-wildcard-routing-#{inspect(routing_ref)}")
        catch
          _, _ -> :ok
        end
      end)

      # Emit different error signals
      Bridge.emit_signal(agent, %{
        id: 1,
        type: "error.validation",
        source: "agent://#{inspect(agent)}",
        data: %{field: "email"}
      })

      Bridge.emit_signal(agent, %{
        id: 2,
        type: "error.timeout",
        source: "agent://#{inspect(agent)}",
        data: %{operation: "api_call"}
      })

      Bridge.emit_signal(agent, %{
        id: 3,
        type: "info.status",
        source: "agent://#{inspect(agent)}",
        data: %{status: "ok"}
      })
      
      # Wait for all 3 signals to be routed
      # error.validation should go to 2 handlers (wildcard + specific)
      assert_receive {^routing_ref, :routing_complete, "error.validation", 2}, 1000
      # error.timeout should go to 1 handler (wildcard only)  
      assert_receive {^routing_ref, :routing_complete, "error.timeout", 1}, 1000
      # info.status should go to 0 handlers (no matches)
      assert_receive {^routing_ref, :routing_complete, "info.status", 0}, 1000

      wildcard_signals = SignalHandler.get_received_signals(wildcard_handler)
      specific_signals = SignalHandler.get_received_signals(specific_handler)

      # Wildcard handler should receive all error signals
      assert length(wildcard_signals) == 2
      assert Enum.any?(wildcard_signals, &(&1.type == "error.validation"))
      assert Enum.any?(wildcard_signals, &(&1.type == "error.timeout"))

      # Specific handler should only receive validation errors
      assert length(specific_signals) == 1
      assert hd(specific_signals).type == "error.validation"
    end
  end
end
