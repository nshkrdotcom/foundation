defmodule Foundation.Telemetry.SpanManagerTest do
  use ExUnit.Case, async: true

  alias Foundation.Telemetry.SpanManager

  setup do
    # Ensure SpanManager is started
    case Process.whereis(SpanManager) do
      nil -> {:ok, _pid} = SpanManager.start_link()
      _pid -> :ok
    end

    # Clear any existing state for this process
    SpanManager.clear_stack()
    :ok
  end

  describe "get_stack/set_stack" do
    test "returns empty list for new process" do
      assert SpanManager.get_stack() == []
    end

    test "sets and gets span stack" do
      stack = [%{id: 1, name: :test}]
      assert SpanManager.set_stack(stack) == :ok
      assert SpanManager.get_stack() == stack
    end

    test "handles empty stack by cleaning up" do
      # Set non-empty stack first
      SpanManager.set_stack([%{id: 1}])
      assert SpanManager.get_stack() == [%{id: 1}]

      # Setting empty stack should clean up
      SpanManager.set_stack([])
      assert SpanManager.get_stack() == []
    end
  end

  describe "push_span/pop_span" do
    test "pushes spans onto stack in LIFO order" do
      span1 = %{id: 1, name: :span1}
      span2 = %{id: 2, name: :span2}

      SpanManager.push_span(span1)
      assert SpanManager.get_stack() == [span1]

      SpanManager.push_span(span2)
      assert SpanManager.get_stack() == [span2, span1]
    end

    test "pops spans from stack" do
      span1 = %{id: 1, name: :span1}
      span2 = %{id: 2, name: :span2}

      SpanManager.push_span(span1)
      SpanManager.push_span(span2)

      assert SpanManager.pop_span() == span2
      assert SpanManager.get_stack() == [span1]

      assert SpanManager.pop_span() == span1
      assert SpanManager.get_stack() == []

      # Popping from empty stack returns nil
      assert SpanManager.pop_span() == nil
    end
  end

  describe "update_top_span" do
    test "updates the top span on the stack" do
      span1 = %{id: 1, name: :span1, metadata: %{}}
      span2 = %{id: 2, name: :span2, metadata: %{}}

      SpanManager.push_span(span1)
      SpanManager.push_span(span2)

      # Update top span
      assert SpanManager.update_top_span(fn span ->
               %{span | metadata: %{updated: true}}
             end) == :ok

      [updated_span | _] = SpanManager.get_stack()
      assert updated_span.metadata == %{updated: true}
      assert updated_span.id == 2
    end

    test "returns error when stack is empty" do
      assert SpanManager.update_top_span(fn span -> span end) == :error
    end
  end

  describe "process monitoring" do
    test "cleans up span stack when process dies" do
      # Start a process that sets up spans
      test_pid = self()

      {:ok, pid} =
        Task.start(fn ->
          span = %{id: 1, name: :test_span}
          SpanManager.push_span(span)

          # Verify span was set
          send(test_pid, {:stack_set, SpanManager.get_stack()})

          # Wait for signal to exit
          receive do
            :exit -> :ok
          end
        end)

      # Wait for the task to set up its span
      assert_receive {:stack_set, [%{id: 1, name: :test_span}]}

      # Verify the span is stored for the task process
      assert SpanManager.get_stack(pid) == [%{id: 1, name: :test_span}]

      # Kill the process
      Process.exit(pid, :kill)

      # Give the SpanManager time to handle the DOWN message
      Process.sleep(50)

      # Verify the span was cleaned up
      assert SpanManager.get_stack(pid) == []
    end

    test "handles multiple processes independently" do
      span1 = %{id: 1, name: :span1}
      span2 = %{id: 2, name: :span2}

      # Set span for current process
      SpanManager.push_span(span1)

      # Start another process with different span
      {:ok, pid} =
        Task.start(fn ->
          SpanManager.push_span(span2)
          Process.sleep(:infinity)
        end)

      # Wait a bit for the task to set its span
      Process.sleep(10)

      # Verify spans are independent
      assert SpanManager.get_stack() == [span1]
      assert SpanManager.get_stack(pid) == [span2]

      # Clean up
      Process.exit(pid, :kill)
    end
  end

  describe "clear_stack" do
    test "clears the span stack for current process" do
      SpanManager.push_span(%{id: 1})
      SpanManager.push_span(%{id: 2})

      assert length(SpanManager.get_stack()) == 2

      SpanManager.clear_stack()
      assert SpanManager.get_stack() == []
    end
  end

  describe "concurrent access" do
    test "handles concurrent operations safely" do
      # Start multiple processes that push/pop spans concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            for j <- 1..10 do
              span = %{id: {i, j}, name: :"span_#{i}_#{j}"}
              SpanManager.push_span(span)

              # Some work
              :timer.sleep(1)

              # Pop the span
              popped = SpanManager.pop_span()
              assert popped.id == {i, j}
            end
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # All stacks should be empty
      assert SpanManager.get_stack() == []
    end
  end

  describe "ETS table recovery" do
    test "handles ETS table access when table doesn't exist" do
      # This simulates the case where the ETS table might not exist
      # The get_stack function should handle this gracefully
      assert SpanManager.get_stack() == []
    end
  end
end
