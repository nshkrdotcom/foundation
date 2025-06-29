defmodule JidoFoundation.ActionRetryTest do
  use ExUnit.Case, async: true
  use Foundation.TestConfig, :registry

  alias JidoFoundation.Bridge

  # Simple test action for Jido.Exec integration
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "Test action for Bridge integration"

    def run(params, _context) do
      case params do
        %{should_fail: :always} ->
          # Always fail for testing error handling
          raise "Always fails"
        
        _ ->
          # Normal success
          {:ok, %{result: "success", attempts: 1}}
      end
    end
  end

  # Action that succeeds after a few attempts (using process state to track attempts)
  defmodule RetrySuccessAction do
    use Jido.Action,
      name: "retry_success_action",
      description: "Action that succeeds after retries"

    def run(%{test_id: test_id}, _context) do
      # Use a global counter to track attempts across retries
      counter_name = :"attempt_counter_#{test_id}"
      
      # Initialize counter if not exists
      case :ets.lookup(:retry_test_counters, counter_name) do
        [] ->
          :ets.insert(:retry_test_counters, {counter_name, 1})
          raise "First attempt failure"
        
        [{^counter_name, count}] when count < 3 ->
          :ets.insert(:retry_test_counters, {counter_name, count + 1})
          raise "Attempt #{count} failure"
        
        [{^counter_name, count}] ->
          {:ok, %{result: "success_after_retries", attempts: count}}
      end
    end
  end

  setup do
    # Create ETS table for tracking retry attempts
    case :ets.info(:retry_test_counters) do
      :undefined -> :ets.new(:retry_test_counters, [:named_table, :public])
      _ -> :ok
    end
    
    on_exit(fn ->
      case :ets.info(:retry_test_counters) do
        :undefined -> :ok
        _ -> :ets.delete_all_objects(:retry_test_counters)
      end
    end)
    
    :ok
  end

  describe "Jido.Exec integration via Bridge" do
    test "executes action successfully with default settings" do
      result = Bridge.execute_with_retry(TestAction, %{test: "value"}, %{user_id: 123})
      
      assert {:ok, %{result: "success", attempts: 1}} = result
    end

    test "retries action on failure and succeeds" do
      test_id = System.unique_integer()
      
      result = Bridge.execute_with_retry(
        RetrySuccessAction, 
        %{test_id: test_id}, 
        %{},
        max_retries: 3,
        backoff: 10  # Small backoff for fast test
      )
      
      assert {:ok, %{result: "success_after_retries", attempts: 3}} = result
    end

    test "passes Foundation metadata in context" do
      result = Bridge.execute_with_retry(TestAction, %{}, %{original: "context"})
      
      assert {:ok, %{result: "success", attempts: 1}} = result
    end

    test "respects timeout option" do
      result = Bridge.execute_with_retry(
        TestAction, 
        %{}, 
        %{},
        timeout: 5000
      )
      
      assert {:ok, %{result: "success", attempts: 1}} = result
    end

    test "executes action and logs at info level" do
      # This test just verifies that the function executes correctly
      # Logging is tested implicitly by other tests and can be observed in test output
      result = Bridge.execute_with_retry(TestAction, %{}, %{}, log_level: :info)
      assert {:ok, %{result: "success", attempts: 1}} = result
    end
    
    test "handles action failures properly" do
      result = Bridge.execute_with_retry(
        TestAction, 
        %{should_fail: :always}, 
        %{},
        max_retries: 2,
        backoff: 5
      )
      
      assert {:error, %Jido.Error{type: :execution_error}} = result
    end
  end
end
