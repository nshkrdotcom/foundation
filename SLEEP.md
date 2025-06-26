# Code Quality Guide: Asynchronous Coordination in Elixir

## The Golden Rule: Don't Sleep, Coordinate

The purpose of this document is to establish a firm standard for handling asynchronous operations and process initialization in our codebase. The use of `:timer.sleep/1` or `Process.sleep/1` to wait for an operation to complete is an anti-pattern that introduces instability and non-determinism. It is strictly forbidden in production code (`lib/`) and strongly discouraged in test code (`test/`).

This guide will explain *why* it's an anti-pattern and provide the correct, idiomatic Elixir/OTP patterns to use instead.

---

## 1. The Problem: Why `sleep` Is Wrong

Using `sleep` is a guess about timing. This guess makes our system fragile, inefficient, and difficult to debug.

*   **It Creates Race Conditions:** A `sleep(100)` might work on your fast development machine but fail on a heavily loaded CI server or in production. The system's state becomes dependent on timing and luck, not on defined logic. This leads to flaky tests and unpredictable production failures.
*   **It's Inefficient:** If the operation you're waiting for finishes in 5ms, a `sleep(100)` wastes 95ms of execution time. If the operation takes 150ms, the system breaks. You are either too slow or wrong.
*   **It Hides Design Flaws:** Using `sleep` is often a symptom of a deeper architectural issue. It indicates that a component isn't providing a clear signal of when its work is complete, or that the developer doesn't trust the guarantees provided by OTP.

## 2. The Core OTP Principle: Synchronous Starts & Explicit Signals

OTP provides robust, built-in mechanisms for coordination. We must trust and use them.

### 2.1. `start_link` is Synchronous

This is the most critical concept to understand. When you call a function like `MyGenServer.start_link(args)` or `Supervisor.start_link(children)`, the function **will not return `{:ok, pid}` until the new process has successfully started, run its `init/1` callback, and is ready to receive messages.**

**This means you almost never need to wait after a successful `start_link` call.**

**Incorrect Code (Anti-Pattern):**
```elixir
case MyWorker.start_link(name: :worker_a) do
  {:ok, pid} ->
    # !! WRONG: This sleep is unnecessary and dangerous.
    Process.sleep(100)
    # The worker was already ready to receive this message.
    MyWorker.do_work(pid, :some_task)

  {:error, reason} ->
    # ... handle error
end
```

**Correct Code:**
```elixir
case MyWorker.start_link(name: :worker_a) do
  {:ok, pid} ->
    # CORRECT: The worker's init/1 has finished. It is ready.
    # We can call it immediately.
    MyWorker.do_work(pid, :some_task)

  {:error, reason} ->
    # ... handle error
end
```

### 2.2. Use Messages for Coordination

If a process needs to perform a long-running initialization *after* its `init/1` callback completes, it must send a signal when it's truly ready. The calling process should wait for this explicit signal, not for an arbitrary amount of time.

**Example: A worker that needs to load data from a database on startup.**

**The Worker (`lib/my_app/worker.ex`):**
```elixir
defmodule MyApp.Worker do
  use GenServer

  # Client API
  def start_link(opts) do
    # The parent_or_caller is passed in so the worker knows who to notify.
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  # GenServer Callbacks
  @impl true
  def init(parent_or_caller: caller_pid) do
    # init/1 should return quickly. We start the long-running task
    # but don't wait for it here.
    send(self(), :load_initial_data)
    {:ok, %{caller: caller_pid, data: nil}}
  end

  @impl true
  def handle_info(:load_initial_data, state) do
    # Simulate a long-running task
    data = Repo.all(DataSchema)

    # !! SIGNAL !!
    # Send an explicit message to the caller that we are ready.
    send(state.caller, {:worker_ready, self()})

    {:noreply, %{state | data: data}}
  end
end
```

**The Caller (e.g., in a supervisor or another GenServer):**
```elixir
# Start the worker
{:ok, worker_pid} = MyApp.Worker.start_link(parent_or_caller: self(), name: :my_worker)

# Wait for the explicit signal
receive do
  {:worker_ready, ^worker_pid} ->
    :ok # Now we know the worker is fully initialized
after
  5_000 ->
    # Fail cleanly if the worker doesn't report back in time.
    exit({:worker_init_timeout, worker_pid})
end

# ... proceed with logic that depends on the worker being ready
```

---

## 3. Practical Guide for Tests (`test/`)

Tests are the most common place to find `sleep`. Flaky tests are a significant drain on developer productivity. The goal is to make tests deterministic by **waiting for an observable effect**, not just for time to pass.

### 3.1. Primary Method: Assert on the Observable Effect

Instead of sleeping, check the result you are actually waiting for.

| Instead of `Process.sleep(100)` and hoping...      | Wait for the actual event...                                                                                                |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| a GenServer's state has changed                    | ...call the GenServer's API to check its state: `assert MyServer.get_state(pid) == :new_state`                              |
| a message was sent to the test process             | ...use `assert_receive` or `assert_received`: `assert_receive {:some_message, "payload"}`                                  |
| a Telemetry event was emitted                      | ...use a Telemetry handler or helper: `Support.Telemetry.assert_event_emitted([:my_app, :event])`                          |
| a log message was written                          | ...use `ExUnit.CaptureLog`: `assert capture_log(fn -> ... end) =~ "expected log message"`                                    |
| a database record was created                      | ...query the database: `assert Repo.get(MySchema, id) != nil`                                                               |

### 3.2. Secondary Method: The `wait_for` Test Helper

For complex asynchronous workflows where the observable effect isn't easy to capture directly, use a standardized helper that polls for a condition to become true, with a proper timeout.

Add this helper to `test/support/concurrent_test_helpers.ex`:
```elixir
defmodule MyApp.ConcurrentTestHelpers do
  @doc """
  Polls a function until it returns a truthy value or a timeout is reached.

  This is an acceptable replacement for `Process.sleep/1` in tests for
  complex async scenarios.
  """
  def wait_for(fun, timeout \\ 1_000, interval \\ 10) do
    start_time = System.monotonic_time(:millisecond)

    check_fun = fn check_fun ->
      if result = fun.() do
        result
      else
        if System.monotonic_time(:millisecond) - start_time > timeout do
          ExUnit.Assertions.flunk("wait_for timed out after #{timeout}ms")
        else
          Process.sleep(interval)
          check_fun.(check_fun)
        end
      end
    end

    check_fun.(check_fun)
  end
end
```

**How to use it in a test:**
```elixir
# Make sure to import the helper in your test file
import MyApp.ConcurrentTestHelpers

test "a background job updates the cache" do
  # This function kicks off an async task
  {:ok, pid} = Cache.start_link()
  Cache.async_rebuild(pid)

  # Instead of Process.sleep(500)
  # We wait until the cache's state is what we expect.
  wait_for(fn -> Cache.get(pid, :rebuilt_key) == :some_expected_value end)

  # The test can now proceed with certainty.
  assert Cache.is_healthy?(pid)
end
```

### 3.3. When is `sleep` Acceptable? (Rare Cases)

1.  **Creating Dummy Test PIDs:** `spawn(fn -> Process.sleep(:infinity) end)` is acceptable in tests to create a "live" PID for testing registries, monitors, etc., where you only need the PID itself, not the process's behavior.
2.  **Testing Time-Based Features:** When testing a rate-limiter or circuit breaker, you may need to use `Process.sleep(window_time + buffer)` to verify that time-based logic is working correctly. This is one of the few legitimate uses.

---

## Summary & Checklist

When writing or refactoring code, follow this checklist:

1.  **Is this in `lib/`?**
    *   [ ] **Never** use `sleep`.
    *   [ ] Do I need to wait after `start_link`? No, trust it's synchronous.
    *   [ ] Is the initialization complex? Use explicit `{:ready, pid}` messages.

2.  **Is this in `test/`?**
    *   [ ] Can I assert on the direct result of the async action (a new state, a received message, a DB record)? **Yes. Do this first.**
    *   [ ] Is it too complex to assert directly? **Use the `wait_for` helper.**
    *   [ ] Am I just creating a fake PID for a test? `spawn(fn -> Process.sleep(:infinity) end)` is fine.
    *   [ ] Am I testing a feature that depends on the passage of time (e.g., a timeout)? `Process.sleep` might be necessary. Scrutinize its use.
