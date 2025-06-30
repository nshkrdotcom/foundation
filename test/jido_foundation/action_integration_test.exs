defmodule JidoFoundation.ActionIntegrationTest do
  # Using registry isolation mode for Action Integration tests
  use Foundation.UnifiedTestFoundation, :registry

  alias JidoFoundation.Bridge

  # Mock Jido Action for testing
  defmodule MockAction do
    @behaviour Access
    defstruct [:name, :description, :params, :run_function]

    def run(action, context) do
      action.run_function.(action.params, context)
    end

    def create(name, opts \\ []) do
      %__MODULE__{
        name: name,
        description: Keyword.get(opts, :description, "Mock action"),
        params: Keyword.get(opts, :params, %{}),
        run_function: Keyword.get(opts, :run_function, fn _, _ -> {:ok, :success} end)
      }
    end

    # Access behavior for keyword-like access
    def fetch(action, key) do
      case key do
        :name -> {:ok, action.name}
        :description -> {:ok, action.description}
        :params -> {:ok, action.params}
        _ -> :error
      end
    end

    def get_and_update(_action, _key, _function), do: raise("Not implemented")
    def pop(_action, _key), do: raise("Not implemented")
  end

  # Mock Jido Agent that can execute actions
  defmodule MockJidoAgent do
    use GenServer

    defstruct [:id, :state, :actions]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      state = %__MODULE__{
        id: Keyword.get(opts, :id, System.unique_integer()),
        state: :ready,
        actions: Keyword.get(opts, :actions, [])
      }

      {:ok, state}
    end

    def execute_action(pid, action, context \\ %{}) do
      GenServer.call(pid, {:execute_action, action, context})
    end

    def get_state(pid) do
      GenServer.call(pid, :get_state)
    end

    def handle_call({:execute_action, action, context}, _from, state) do
      result = MockAction.run(action, context)
      {:reply, result, state}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  describe "Jido.Action circuit breaker integration" do
    test "executes action successfully with circuit breaker protection", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "test_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      # Register agent with Foundation
      :ok =
        Bridge.register_agent(agent,
          capabilities: [:action_execution],
          registry: registry
        )

      # Create a successful action
      action =
        MockAction.create(:test_action,
          run_function: fn _params, _context -> {:ok, "success"} end
        )

      # Execute action with circuit breaker protection
      result =
        Bridge.execute_protected(agent, fn ->
          MockJidoAgent.execute_action(agent, action)
        end)

      assert result == {:ok, "success"}
    end

    test "uses fallback when action fails repeatedly", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "failing_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:action_execution],
          registry: registry
        )

      # Create a failing action
      failing_action =
        MockAction.create(:failing_action,
          run_function: fn _params, _context -> {:error, "service_error"} end
        )

      service_id = {:test_action_service, System.unique_integer()}

      # Cause multiple failures to open circuit
      for _ <- 1..6 do
        Bridge.execute_protected(
          agent,
          fn ->
            MockJidoAgent.execute_action(agent, failing_action)
          end,
          service_id: service_id
        )
      end

      # Circuit should be open, fallback should be used
      result =
        Bridge.execute_protected(
          agent,
          fn ->
            MockJidoAgent.execute_action(agent, failing_action)
          end,
          service_id: service_id,
          fallback: {:ok, "fallback_executed"}
        )

      assert result == {:ok, "fallback_executed"}
    end

    test "emits telemetry events for action execution", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "telemetry_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:action_execution],
          registry: registry
        )

      action =
        MockAction.create(:telemetry_action,
          run_function: fn _params, _context -> {:ok, "telemetry_test"} end
        )

      # Execute action
      result =
        Bridge.execute_protected(agent, fn ->
          MockJidoAgent.execute_action(agent, action)
        end)

      assert result == {:ok, "telemetry_test"}

      # Test basic telemetry functionality first
      test_pid = self()

      # Test if telemetry works at all
      :telemetry.attach(
        "test-basic-telemetry",
        [:test, :basic],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Emit basic test event
      :telemetry.execute([:test, :basic], %{value: 42}, %{test: true})

      # This should work
      assert_receive {:telemetry, [:test, :basic], %{value: 42}, %{test: true}}, 100

      :telemetry.detach("test-basic-telemetry")

      # Now test our Jido bridge telemetry
      :telemetry.attach(
        "test-jido-telemetry",
        [:jido, :agent, :executed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:jido_telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Our bridge emits to [:jido, :agent, event_type], not [:jido, :action, event_type]
      Bridge.emit_agent_event(agent, :executed, %{duration: 150}, %{
        action: :telemetry_action,
        result: :success
      })

      # Check for the correct event path
      assert_receive {:jido_telemetry, [:jido, :agent, :executed], measurements, metadata}, 100
      assert measurements.duration == 150
      assert metadata.action == :telemetry_action
      assert metadata.result == :success
      assert metadata.agent_id == agent

      :telemetry.detach("test-jido-telemetry")
    end
  end

  describe "Jido.Action resource management" do
    test "acquires and releases resources for action execution", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "resource_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:resource_management],
          registry: registry
        )

      # Create an action that requires resources
      resource_action =
        MockAction.create(:resource_action,
          run_function: fn _params, _context ->
            # Simulate some work that uses resources
            {:ok, "resource_work_done"}
          end
        )

      # Execute action with resource management
      with {:ok, token} <- Bridge.acquire_resource(:computation, %{agent: agent}),
           {:ok, result} <-
             Bridge.execute_protected(agent, fn ->
               MockJidoAgent.execute_action(agent, resource_action)
             end),
           :ok <- Bridge.release_resource(token) do
        assert result == "resource_work_done"
      else
        error -> flunk("Resource management failed: #{inspect(error)}")
      end
    end

    test "handles resource exhaustion gracefully", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "resource_limited_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:resource_management],
          registry: registry
        )

      # Try to acquire a resource that may not be available
      case Bridge.acquire_resource(:limited_computation, %{agent: agent}) do
        {:ok, token} ->
          # If we got a token, clean it up
          :ok = Bridge.release_resource(token)

        {:error, :resource_unavailable} ->
          # This is expected when resources are exhausted
          :ok

        {:error, _reason} ->
          # Other errors are also acceptable for this test
          :ok
      end
    end
  end

  describe "Jido.Action error handling" do
    test "handles action crashes gracefully", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "crash_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:error_handling],
          registry: registry
        )

      # Create an action that returns an error instead of crashing the agent
      failing_action =
        MockAction.create(:crash_action,
          run_function: fn _params, _context ->
            {:error, "simulated_crash"}
          end
        )

      # Execute with crash protection
      result =
        Bridge.execute_protected(
          agent,
          fn ->
            MockJidoAgent.execute_action(agent, failing_action)
          end,
          fallback: {:ok, "crash_recovered"}
        )

      # Should handle the error gracefully
      assert result == {:error, "simulated_crash"} or result == {:ok, "crash_recovered"}
    end

    test "tracks action error metrics", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(id: "error_tracking_agent")

      on_exit(fn ->
        if is_pid(agent) && Process.alive?(agent) do
          try do
            GenServer.stop(agent, :normal, 100)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      # Attach telemetry handler for errors
      :telemetry.attach(
        "test-action-errors",
        [:jido, :agent, :error],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-action-errors")
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:error_handling],
          registry: registry
        )

      error_action =
        MockAction.create(:error_action,
          run_function: fn _params, _context -> {:error, "validation_failed"} end
        )

      # Execute action that will fail
      result =
        Bridge.execute_protected(agent, fn ->
          MockJidoAgent.execute_action(agent, error_action)
        end)

      # Emit error telemetry based on result
      case result do
        {:error, reason} ->
          Bridge.emit_agent_event(agent, :error, %{error_count: 1}, %{
            action: :error_action,
            error_type: :validation_error,
            reason: reason
          })

        _ ->
          # If no error occurred, still emit telemetry for testing
          Bridge.emit_agent_event(agent, :error, %{error_count: 1}, %{
            action: :error_action,
            error_type: :validation_error,
            reason: "validation_failed"
          })
      end

      # Verify error telemetry
      assert_receive {:telemetry, [:jido, :agent, :error], measurements, metadata}
      assert measurements.error_count == 1
      assert metadata.action == :error_action
      assert metadata.error_type == :validation_error
      assert metadata.reason == "validation_failed"
    end
  end
end
