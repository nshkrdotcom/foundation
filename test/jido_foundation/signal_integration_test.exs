defmodule JidoFoundation.SignalIntegrationTest do
  # Using registry isolation mode for signal integration tests
  use Foundation.UnifiedTestFoundation, :registry

  alias JidoFoundation.Bridge

  # Mock Jido Signal structure for testing
  defmodule MockSignal do
    @behaviour Access
    defstruct [:id, :type, :source, :data, :time, :metadata]

    def create(type, source, data, opts \\ []) do
      %__MODULE__{
        id: Keyword.get(opts, :id, System.unique_integer()),
        type: type,
        source: source,
        data: data,
        time: Keyword.get(opts, :time, DateTime.utc_now()),
        metadata: Keyword.get(opts, :metadata, %{})
      }
    end

    # CloudEvents v1.0.2 compatible format
    def to_cloudevent(signal) do
      %{
        specversion: "1.0",
        type: signal.type,
        source: signal.source,
        id: to_string(signal.id),
        time: DateTime.to_iso8601(signal.time),
        datacontenttype: "application/json",
        data: signal.data,
        subject: Map.get(signal.metadata, :subject),
        extensions: Map.drop(signal.metadata, [:subject])
      }
    end

    # Access behavior for keyword-like access
    def fetch(signal, key) do
      case key do
        :id -> {:ok, signal.id}
        :type -> {:ok, signal.type}
        :source -> {:ok, signal.source}
        :data -> {:ok, signal.data}
        :time -> {:ok, signal.time}
        :metadata -> {:ok, signal.metadata}
        _ -> :error
      end
    end

    def get_and_update(_signal, _key, _function), do: raise("Not implemented")
    def pop(_signal, _key), do: raise("Not implemented")
  end

  # Mock Jido Agent that can emit signals
  defmodule SignalEmittingAgent do
    use GenServer

    defstruct [:id, :state, :signal_handlers]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      state = %__MODULE__{
        id: Keyword.get(opts, :id, System.unique_integer()),
        state: :ready,
        signal_handlers: Keyword.get(opts, :signal_handlers, [])
      }

      {:ok, state}
    end

    def emit_signal(pid, signal) do
      GenServer.call(pid, {:emit_signal, signal})
    end

    def add_signal_handler(pid, handler) do
      GenServer.call(pid, {:add_signal_handler, handler})
    end

    def get_state(pid) do
      GenServer.call(pid, :get_state)
    end

    def handle_call({:emit_signal, signal}, _from, state) do
      # Process signal through handlers with crash protection
      Enum.each(state.signal_handlers, fn handler ->
        try do
          handler.(signal)
        catch
          kind, reason ->
            # Log crash but continue with other handlers
            IO.puts("Handler crashed: #{kind} #{inspect(reason)}")
        end
      end)

      {:reply, :ok, state}
    end

    def handle_call({:add_signal_handler, handler}, _from, state) do
      new_handlers = [handler | state.signal_handlers]
      new_state = %{state | signal_handlers: new_handlers}
      {:reply, :ok, new_state}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  describe "Jido.Signal Foundation integration" do
    test "emits signals through Foundation telemetry", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "signal_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      # Register agent with Foundation
      :ok =
        Bridge.register_agent(agent,
          capabilities: [:signal_emission],
          registry: registry
        )

      # Attach telemetry handler for signal events
      test_pid = self()

      :telemetry.attach(
        "test-signal-events",
        [:jido, :signal, :emitted],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-signal-events")
      end)

      # Create a signal
      signal =
        MockSignal.create("task.completed", "agent://#{inspect(agent)}", %{
          task_id: "task_123",
          result: "success",
          duration: 150
        })

      # Emit signal through Foundation
      Bridge.emit_signal(agent, signal)

      # Verify telemetry event was emitted
      assert_receive {:telemetry, [:jido, :signal, :emitted], measurements, metadata}
      assert measurements.signal_id == signal.id
      assert metadata.agent_id == agent
      assert metadata.signal_type == "task.completed"
      assert metadata.framework == :jido
    end

    test "routes signals to multiple handlers", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "routing_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:signal_routing],
          registry: registry
        )

      # Set up signal handlers that send messages to the test process
      test_pid = self()

      handler1 = fn signal ->
        send(test_pid, {:handler1, signal.type, signal.data})
      end

      handler2 = fn signal ->
        send(test_pid, {:handler2, signal.type, signal.data})
      end

      # Add handlers to the agent
      :ok = SignalEmittingAgent.add_signal_handler(agent, handler1)
      :ok = SignalEmittingAgent.add_signal_handler(agent, handler2)

      # Create and emit a signal
      signal =
        MockSignal.create("workflow.started", "agent://#{inspect(agent)}", %{
          workflow_id: "wf_456",
          step: "initialization"
        })

      :ok = SignalEmittingAgent.emit_signal(agent, signal)

      # Verify both handlers received the signal
      assert_receive {:handler1, "workflow.started", %{workflow_id: "wf_456"}}
      assert_receive {:handler2, "workflow.started", %{workflow_id: "wf_456"}}
    end

    test "converts signals to CloudEvents format", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "cloudevents_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:cloudevents],
          registry: registry
        )

      # Create a signal with metadata
      signal =
        MockSignal.create(
          "data.processed",
          "agent://#{inspect(agent)}",
          %{
            records_processed: 1000,
            processing_time: 2500
          },
          metadata: %{
            subject: "data-pipeline",
            priority: "high",
            correlation_id: "corr_789"
          }
        )

      # Convert to CloudEvent format
      cloudevent = Bridge.signal_to_cloudevent(signal)

      # Verify CloudEvent structure
      assert cloudevent[:specversion] == "1.0"
      assert cloudevent[:type] == "data.processed"
      assert cloudevent[:source] == "agent://#{inspect(agent)}"
      assert cloudevent[:id] == to_string(signal.id)
      assert cloudevent[:datacontenttype] == "application/json"
      assert cloudevent[:data] == %{records_processed: 1000, processing_time: 2500}
      assert cloudevent[:subject] == "data-pipeline"
      assert cloudevent[:extensions][:priority] == "high"
      assert cloudevent[:extensions][:correlation_id] == "corr_789"
    end

    test "filters signals by type", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "filtering_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:signal_filtering],
          registry: registry
        )

      # Set up filtered signal handler
      test_pid = self()

      filtered_handler = fn signal ->
        if String.starts_with?(signal.type, "error.") do
          send(test_pid, {:error_signal, signal.type, signal.data})
        end
      end

      :ok = SignalEmittingAgent.add_signal_handler(agent, filtered_handler)

      # Emit various signal types
      error_signal =
        MockSignal.create("error.validation", "agent://#{inspect(agent)}", %{
          field: "email",
          message: "Invalid format"
        })

      info_signal =
        MockSignal.create("info.status", "agent://#{inspect(agent)}", %{
          status: "processing"
        })

      warning_signal =
        MockSignal.create("error.timeout", "agent://#{inspect(agent)}", %{
          operation: "database_query",
          timeout: 30
        })

      :ok = SignalEmittingAgent.emit_signal(agent, error_signal)
      :ok = SignalEmittingAgent.emit_signal(agent, info_signal)
      :ok = SignalEmittingAgent.emit_signal(agent, warning_signal)

      # Verify only error signals were processed
      assert_receive {:error_signal, "error.validation", %{field: "email"}}
      assert_receive {:error_signal, "error.timeout", %{operation: "database_query"}}

      # Should not receive the info signal
      refute_receive {:error_signal, "info.status", _}
    end

    test "correlates signals across agents", %{registry: registry} do
      {:ok, agent1} = SignalEmittingAgent.start_link(id: "correlator_agent_1")
      {:ok, agent2} = SignalEmittingAgent.start_link(id: "correlator_agent_2")

      on_exit(fn ->
        if Process.alive?(agent1), do: GenServer.stop(agent1)
        if Process.alive?(agent2), do: GenServer.stop(agent2)
      end)

      :ok = Bridge.register_agent(agent1, capabilities: [:correlation], registry: registry)
      :ok = Bridge.register_agent(agent2, capabilities: [:correlation], registry: registry)

      # Create correlated signals with the same correlation ID
      correlation_id = "workflow_batch_#{System.unique_integer()}"

      signal1 =
        MockSignal.create(
          "task.started",
          "agent://#{inspect(agent1)}",
          %{
            task_id: "task_001"
          },
          metadata: %{correlation_id: correlation_id, step: 1}
        )

      signal2 =
        MockSignal.create(
          "task.completed",
          "agent://#{inspect(agent2)}",
          %{
            task_id: "task_001",
            result: "success"
          },
          metadata: %{correlation_id: correlation_id, step: 2}
        )

      # Set up correlation tracker
      test_pid = self()

      correlation_tracker = fn signal ->
        if signal.metadata[:correlation_id] == correlation_id do
          send(test_pid, {:correlated_signal, signal.metadata[:step], signal.type})
        end
      end

      :ok = SignalEmittingAgent.add_signal_handler(agent1, correlation_tracker)
      :ok = SignalEmittingAgent.add_signal_handler(agent2, correlation_tracker)

      # Emit correlated signals
      :ok = SignalEmittingAgent.emit_signal(agent1, signal1)
      :ok = SignalEmittingAgent.emit_signal(agent2, signal2)

      # Verify correlation
      assert_receive {:correlated_signal, 1, "task.started"}
      assert_receive {:correlated_signal, 2, "task.completed"}
    end
  end

  describe "Jido.Signal error handling" do
    test "handles signal emission failures gracefully", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "error_handling_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:error_handling],
          registry: registry
        )

      # Add a handler that crashes
      crashing_handler = fn _signal ->
        raise "Handler crashed"
      end

      # Add a normal handler
      test_pid = self()

      normal_handler = fn signal ->
        send(test_pid, {:normal_handler, signal.type})
      end

      :ok = SignalEmittingAgent.add_signal_handler(agent, crashing_handler)
      :ok = SignalEmittingAgent.add_signal_handler(agent, normal_handler)

      # Create a signal
      signal = MockSignal.create("test.signal", "agent://#{inspect(agent)}", %{test: true})

      # Emit signal - should handle crash gracefully
      result = Bridge.emit_signal_protected(agent, signal)

      # Should return ok even if some handlers crash
      assert result == :ok

      # Also trigger the signal handlers directly to test the crashing behavior
      :ok = SignalEmittingAgent.emit_signal(agent, signal)

      # Normal handler should still receive the signal despite the crashing handler
      assert_receive {:normal_handler, "test.signal"}
    end

    test "tracks signal emission metrics", %{registry: registry} do
      {:ok, agent} = SignalEmittingAgent.start_link(id: "metrics_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      # Attach telemetry handler for signal metrics
      test_pid = self()

      :telemetry.attach(
        "test-signal-metrics",
        [:jido, :agent, :metrics],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-signal-metrics")
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:metrics],
          registry: registry
        )

      # Emit multiple signals and track metrics
      for i <- 1..5 do
        signal = MockSignal.create("batch.item", "agent://#{inspect(agent)}", %{item: i})
        Bridge.emit_signal(agent, signal)
      end

      # Emit metrics summary
      Bridge.emit_agent_event(agent, :metrics, %{signals_emitted: 5}, %{
        signal_types: ["batch.item"],
        agent_id: agent
      })

      # Verify metrics telemetry
      assert_receive {:telemetry, [:jido, :agent, :metrics], measurements, metadata}
      assert measurements.signals_emitted == 5
      assert metadata.signal_types == ["batch.item"]
      assert metadata.agent_id == agent
    end
  end
end
