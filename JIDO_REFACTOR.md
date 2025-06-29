# TASK LIST: JIDO REFACTOR - Phase 2.3a

## Phase 2.3a.1: Jido Execution Integration (Week 1)
- [ ] **Replace Custom Retry Logic** - Remove all custom retry loops in `JidoFoundation.Bridge` and `JidoSystem.Actions.ProcessTask`
- [ ] **Implement Jido.Exec Integration** - Replace custom retry with `Jido.Exec.run/4` with `:max_retries` and `:backoff` options
- [ ] **Test Execution Integration** - Comprehensive tests for Jido.Exec retry logic
- [ ] **Update Bridge Module** - Refactor `JidoFoundation.Bridge.execute_with_retry` to use Jido.Exec
- [ ] **Validate Zero Regressions** - All existing tests continue to pass

## Phase 2.3a.2: Directive System Adoption (Week 2)  
- [ ] **Refactor State-Changing Actions** - Convert `QueueTask`, `PauseProcessing`, `ResumeProcessing` to use `Jido.Agent.Directive.StateModification`
- [ ] **Remove Custom State Logic** - Eliminate custom key-based state modification in `on_after_run` callbacks
- [ ] **Implement Directive Returns** - Actions return proper `StateModification` directives instead of result maps
- [ ] **Test Directive Integration** - Comprehensive tests for directive-based state changes  
- [ ] **Validate Agent State Management** - All agents correctly process directives

## Phase 2.3a.3: Instruction/Runner Model Integration (Week 3)
- [ ] **Refactor Bridge Interactions** - External interactions use `Jido.Instruction.new!` instead of direct action calls
- [ ] **Implement Agent Casting** - Bridge creates instructions and casts to agents properly
- [ ] **Test Instruction Processing** - Comprehensive tests for instruction-based execution
- [ ] **Validate Runner Integration** - Agents process instructions through their configured runners
- [ ] **Remove Direct Action Calls** - Eliminate bypassing of instruction/runner model

## Phase 2.3a.4: Signal System Integration (Week 4)
- [ ] **Evaluate jido_signal Adoption** - Analysis of custom SignalRouter vs Jido.Signal.Bus
- [ ] **Implement Jido.Signal.Bus** - Replace custom router with feature-rich Jido signal system
- [ ] **Add Signal Middleware** - Leverage Jido signal middleware capabilities
- [ ] **Test Signal Integration** - Comprehensive tests for Jido signal dispatch
- [ ] **Validate Signal Features** - Persistent subscriptions and multiple dispatch adapters working

## Success Metrics for Phase 2.3a:
- ✅ **All Tests Passing** - Zero regressions from Jido integration improvements
- ✅ **Proper Jido Usage** - Actions use Jido.Exec, agents use Directive system, interactions use Instructions
- ✅ **Enhanced Signal System** - Jido.Signal.Bus provides advanced signal features
- ✅ **Reduced Technical Debt** - Elimination of custom implementations that duplicate Jido features
- ✅ **Improved Maintainability** - Leveraging battle-tested Jido library features

---

Of course. I will review the provided codebases to assess how the `Jido` library has been integrated into the `Foundation`/`JidoSystem` application.

This review compares the implementation in the main codebase (from the first prompt) against the features and intended usage patterns of the `Jido` libraries (`relib.xml`, `r1.xml`) and their documentation (`jaguides.xml`).

### Overall Assessment of Jido Integration

The integration of Jido is functional but incomplete. The developers have correctly adopted the core concepts of `Jido.Action` and `Jido.Agent` for defining components. However, they have missed or reimplemented several of Jido's more advanced, production-ready features, particularly around execution, state management, and signal dispatch. This has led to a custom-built integration layer (`JidoFoundation.Bridge`) that reinvents functionality already present in the Jido library, potentially introducing bugs and maintenance overhead.

---

### Detailed Review of Jido Feature Integration

#### 1. Agent Definition (`Jido.Agent`)

**Correctness:** **Excellent**
**Leverage:** **Good**

The system correctly uses `use Jido.Agent` to define stateful agents like `TaskAgent`, `MonitorAgent`, and `CoordinatorAgent` (via the `FoundationAgent` macro).

-   **Schema Definition:** The use of `schema: [...]` to define the agent's state structure is idiomatic and correct.
-   **Action Registration:** Actions are correctly registered at compile-time via the `actions: [...]` option.
-   **Lifecycle Callbacks:** The agents correctly implement OTP-style callbacks like `mount/2` and `on_error/2`, demonstrating a good understanding of the agent lifecycle.

The `FoundationAgent` module provides a solid base for all system agents, which is a good pattern for adding shared functionality.

#### 2. Action Definition (`Jido.Action`)

**Correctness:** **Excellent**
**Leverage:** **Good**

The action modules (e.g., `JidoSystem.Actions.ProcessTask`) correctly use `use Jido.Action` and define a `schema` for their parameters. They also correctly implement the `run/2` callback. This is the intended way to define discrete units of work.

#### 3. Action Execution (`Jido.Exec`) & Runners (`Jido.Runner`)

**Correctness:** **Incorrect**
**Leverage:** **Poor**

This is the most significant area of incorrect integration. The `Jido.Exec` module is designed to be the primary interface for running actions, providing built-in features for retries, timeouts, and telemetry.

-   **Reimplemented Retry Logic:** `JidoFoundation.Bridge.execute_with_retry` and `JidoSystem.Actions.ProcessTask` both implement their own custom retry logic. The `Jido.Exec.run/4` function already provides this feature via the `:max_retries` and `:backoff` options, which is being completely ignored.
    -   **File:** `jido/exec.ex` in `r1.xml` shows the `do_run_with_retry` private function, which handles this logic automatically.
    -   **Recommendation:** Replace the custom retry loops with calls to `Jido.Exec.run(action, params, context, max_retries: 3, backoff: 500)`. This would simplify the code and leverage the library's battle-tested implementation.

-   **Bypassing the Runner Model:** The `JidoFoundation.Bridge` module calls actions directly (e.g., `Foundation.ErrorHandler.with_recovery(protected_fun, ...)`), bypassing the agent's configured `runner`. The Jido agent model is built around a `runner` (like `Jido.Runner.Simple` or `Jido.Runner.Chain`) that processes the agent's instruction queue. Direct execution is meant for testing, not as a primary interaction pattern. This bypasses features like result chaining and queue management.

#### 4. Agent Directives (`Jido.Agent.Directive`)

**Correctness:** **N/A (Not Used)**
**Leverage:** **None**

The `Jido` library provides a `Directive` system for actions to declaratively modify the agent's state or behavior (e.g., `%Directive.StateModification{op: :set, ...}`). This is a core feature for safe, auditable state changes.

The current implementation completely ignores this system. Instead, it relies on custom patterns where actions return special keys in their result maps (e.g., `%{updated_queue: ...}` in `JidoSystem.Actions.QueueTask`), and the `TaskAgent`'s `on_after_run` callback inspects this map to imperatively modify state.

-   **Missed Opportunity:** Using directives would make the actions more reusable and the state changes more explicit and less coupled to the `on_after_run` implementation.
-   **Recommendation:** Refactor actions like `QueueTask`, `PauseProcessing`, and `ResumeProcessing` to return `StateModification` directives instead of result maps with special keys. This aligns with the intended design of the Jido library.

#### 5. Signals & Dispatch (`Jido.Signal`)

**Correctness:** **Partial**
**Leverage:** **Partial**

The system uses the concept of signals, but it has reimplemented the entire dispatch and routing mechanism instead of using the one provided by the `jido_signal` library.

-   **Custom Router:** The `JidoFoundation.SignalRouter` is a custom `GenServer` that listens to `:telemetry` events. The `jido_signal` library, however, provides its own sophisticated, trie-based `Jido.Signal.Router` and a `Jido.Signal.Bus` for managing subscriptions and dispatching.
-   **Dispatch:** The `JidoFoundation.Bridge` calls `:telemetry.execute` to emit signals. The `jido_signal` library provides `Jido.Signal.Dispatch.dispatch/2`, which supports multiple adapters (e.g., `:pid`, `:pubsub`, `:http`, `:webhook`).

This custom implementation might have been an intentional design choice to decouple from `jido_signal`'s bus, but it means the project is not leveraging the library's full feature set, including persistent subscriptions, middleware, and various dispatch adapters.

#### 6. Instructions (`Jido.Instruction`)

**Correctness:** **Good**
**Leverage:** **Partial**

The `JidoSystem.Agents.TaskAgent` correctly uses `Jido.Instruction.new!` to create instructions and enqueues them for self-execution. This is a good example of leveraging the instruction system for an agent's internal work loop.

However, most external interactions via `JidoFoundation.Bridge` do not create `Instruction` structs. They call actions directly, which bypasses the rich context and options (`opts`) that `Instruction`s provide.

### Summary of Recommendations

1.  **Refactor Retry Logic:** Remove all custom-written retry loops in `JidoFoundation.Bridge` and `JidoSystem.Actions.ProcessTask`. Replace them with calls to `Jido.Exec.run/4`, passing the `:max_retries` and `:backoff` options.
2.  **Adopt the Directive System:** Modify state-changing actions (`QueueTask`, `PauseProcessing`, etc.) to return `Jido.Agent.Directive.StateModification` structs instead of maps with custom keys. This will simplify the `on_after_run` callbacks and align with Jido's intended design for state management.
3.  **Use the Instruction/Runner Model:** Interactions with agents should primarily happen by creating an `Instruction` and `cast`ing it to the agent. This ensures the agent's `runner` correctly processes the work and allows for more advanced execution strategies (like `Jido.Runner.Chain`). The direct action calls in the `Bridge` should be refactored.
4.  **Evaluate `jido_signal` Adoption:** Review the custom `SignalRouter`. Consider replacing it with the more feature-rich `Jido.Signal.Bus` and `Jido.Signal.Router` to gain access to persistent subscriptions, middleware, and multiple dispatch adapters out of the box.
