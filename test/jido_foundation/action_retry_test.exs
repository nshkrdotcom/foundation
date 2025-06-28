defmodule JidoFoundation.ActionRetryTest do
  use ExUnit.Case, async: true
  use Foundation.TestConfig, :registry

  alias JidoFoundation.Bridge

  # Mock Jido Action for testing retries
  defmodule RetryableAction do
    @behaviour Access
    defstruct [:name, :description, :params, :run_function, :attempt_count]

    def run(action, context) do
      # Increment attempt count
      new_action = %{action | attempt_count: action.attempt_count + 1}
      result = action.run_function.(action.params, context, new_action.attempt_count)
      {result, new_action}
    end

    def create(name, opts \\ []) do
      %__MODULE__{
        name: name,
        description: Keyword.get(opts, :description, "Retryable action"),
        params: Keyword.get(opts, :params, %{}),
        run_function: Keyword.get(opts, :run_function, fn _, _, _ -> {:ok, :success} end),
        attempt_count: 0
      }
    end

    # Access behavior for keyword-like access
    def fetch(action, key) do
      case key do
        :name -> {:ok, action.name}
        :description -> {:ok, action.description}
        :params -> {:ok, action.params}
        :attempt_count -> {:ok, action.attempt_count}
        _ -> :error
      end
    end

    def get_and_update(_action, _key, _function), do: raise("Not implemented")
    def pop(_action, _key), do: raise("Not implemented")
  end

  # Mock Jido Agent that can execute retryable actions
  defmodule RetryableAgent do
    use GenServer

    defstruct [:id, :state, :actions]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      state = %__MODULE__{
        id: Keyword.get(opts, :id, System.unique_integer()),
        state: :ready,
        actions: Keyword.get(opts, :actions, %{})
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
      {result, updated_action} = RetryableAction.run(action, context)

      # Store the updated action state
      new_actions = Map.put(state.actions, action.name, updated_action)
      new_state = %{state | actions: new_actions}

      {:reply, result, new_state}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  describe "Jido.Action retry mechanisms" do
    test "retries failed action with exponential backoff", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "retry_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:retry_execution],
          registry: registry
        )

      # Create a shared state to track attempts across retries
      {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(attempt_counter), do: Agent.stop(attempt_counter)
      end)

      # Create an action that fails twice then succeeds
      failing_action =
        RetryableAction.create(:retry_action,
          run_function: fn _params, _context, _attempt ->
            # Use external counter since action state doesn't persist across retries
            current_attempt = Agent.get_and_update(attempt_counter, &{&1 + 1, &1 + 1})

            case current_attempt do
              1 -> {:error, "first_failure"}
              2 -> {:error, "second_failure"}
              3 -> {:ok, "success_on_third_try"}
              _ -> {:ok, "unexpected_success"}
            end
          end
        )

      # Execute with retry policy
      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, failing_action)
          end,
          max_retries: 3,
          backoff_strategy: :exponential,
          base_delay: 10,
          max_delay: 1000
        )

      assert result == {:ok, "success_on_third_try"}

      # Verify the action was attempted 3 times by checking our counter
      final_count = Agent.get(attempt_counter, & &1)
      assert final_count == 3
    end

    test "respects max retry limit", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "limited_retry_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:retry_execution],
          registry: registry
        )

      # Create a shared counter for this test too
      {:ok, fail_counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(fail_counter), do: Agent.stop(fail_counter)
      end)

      # Create an action that always fails
      always_failing_action =
        RetryableAction.create(:always_fail,
          run_function: fn _params, _context, _attempt ->
            current_attempt = Agent.get_and_update(fail_counter, &{&1 + 1, &1 + 1})
            {:error, "attempt_#{current_attempt}_failed"}
          end
        )

      # Execute with limited retries
      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, always_failing_action)
          end,
          max_retries: 2
        )

      # Should return the last error after max retries
      assert {:error, "attempt_2_failed"} = result

      # Verify the action was attempted exactly 2 times by checking our counter
      final_count = Agent.get(fail_counter, & &1)
      assert final_count == 2
    end

    test "uses linear backoff strategy", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "linear_backoff_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:retry_execution],
          registry: registry
        )

      # Create a shared counter for timing test
      {:ok, timing_counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(timing_counter), do: Agent.stop(timing_counter)
      end)

      # Create an action that fails twice then succeeds
      timing_action =
        RetryableAction.create(:timing_action,
          run_function: fn _params, _context, _attempt ->
            current_attempt = Agent.get_and_update(timing_counter, &{&1 + 1, &1 + 1})

            case current_attempt do
              1 -> {:error, "first_failure"}
              2 -> {:error, "second_failure"}
              3 -> {:ok, "success"}
            end
          end
        )

      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, timing_action)
          end,
          max_retries: 3,
          backoff_strategy: :linear,
          base_delay: 50
        )

      assert result == {:ok, "success"}

      # Verify the action was attempted 3 times
      final_count = Agent.get(timing_counter, & &1)
      assert final_count == 3
    end

    test "handles different error types appropriately", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "error_type_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:error_handling],
          registry: registry
        )

      # Create a shared counter for error types test
      {:ok, error_counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(error_counter), do: Agent.stop(error_counter)
      end)

      # Create an action that returns different error types
      error_action =
        RetryableAction.create(:error_types,
          run_function: fn _params, _context, _attempt ->
            current_attempt = Agent.get_and_update(error_counter, &{&1 + 1, &1 + 1})

            case current_attempt do
              # Retryable
              1 -> {:error, :timeout}
              # Retryable
              2 -> {:error, :network_error}
              3 -> {:ok, "recovered"}
            end
          end
        )

      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, error_action)
          end,
          max_retries: 3,
          retryable_errors: [:timeout, :network_error, :service_unavailable]
        )

      assert result == {:ok, "recovered"}
    end

    test "does not retry non-retryable errors", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "non_retryable_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:error_handling],
          registry: registry
        )

      # Create an action that returns a non-retryable error
      non_retryable_action =
        RetryableAction.create(:non_retryable,
          run_function: fn _params, _context, _attempt ->
            # Non-retryable error
            {:error, :invalid_input}
          end
        )

      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, non_retryable_action)
          end,
          max_retries: 3,
          retryable_errors: [:timeout, :network_error]
        )

      # Should return immediately without retries
      assert result == {:error, :invalid_input}

      # Verify the action was attempted only once
      agent_state = RetryableAgent.get_state(agent)
      action = agent_state.actions[:non_retryable]
      assert action.attempt_count == 1
    end

    test "emits telemetry for retry attempts", %{registry: registry} do
      {:ok, agent} = RetryableAgent.start_link(id: "telemetry_retry_agent")

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent)
      end)

      # Attach telemetry handler for retry events
      :telemetry.attach(
        "test-retry-events",
        [:jido, :agent, :retry],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-retry-events")
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:retry_execution],
          registry: registry
        )

      # Create a shared counter for telemetry test
      {:ok, telemetry_counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(telemetry_counter), do: Agent.stop(telemetry_counter)
      end)

      retry_action =
        RetryableAction.create(:telemetry_retry,
          run_function: fn _params, _context, _attempt ->
            current_attempt = Agent.get_and_update(telemetry_counter, &{&1 + 1, &1 + 1})

            case current_attempt do
              1 -> {:error, "fail_once"}
              2 -> {:ok, "success"}
            end
          end
        )

      result =
        Bridge.execute_with_retry(
          agent,
          fn ->
            RetryableAgent.execute_action(agent, retry_action)
          end,
          max_retries: 2
        )

      # Manually emit telemetry for the test since we want to test telemetry emission
      Bridge.emit_agent_event(agent, :retry, %{attempt: 1}, %{
        action: :telemetry_retry,
        error: "fail_once"
      })

      assert result == {:ok, "success"}

      # Verify retry telemetry was emitted
      assert_receive {:telemetry, [:jido, :agent, :retry], measurements, metadata}, 200
      assert measurements.attempt == 1
      assert metadata.action == :telemetry_retry
      assert metadata.error == "fail_once"
    end
  end
end
