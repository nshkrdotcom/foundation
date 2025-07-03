Of course. Based on the provided prompts and the state of the codebase (which is at the completion of Prompt 2), here is a consolidated plan for what is needed to implement the feature flag system as described in Prompt 8.

### 1. Analysis of Current State (Codebase @ Prompt 2)

Before planning, it's crucial to understand what already exists. After completing Prompt 2, the codebase has the following relevant features:

*   **Feature Flag Module Exists**: The file `lib/foundation/feature_flags.ex` exists. It's a `GenServer` that manages flags in an ETS table.
*   **Initial Flag Implementation is Done**: The `use_ets_agent_registry` flag from Prompt 2 is already implemented. The file `lib/foundation/protocols/registry_any.ex` contains the logic to switch between the legacy Process Dictionary implementation and the new ETS-based one (`Foundation.Protocols.RegistryETS`).
*   **Other Modules are Unchanged**: The modules targeted by Prompts 3-7 (`MABEAM.AgentRegistry`, `Foundation.ErrorContext`, `Foundation.Telemetry.SampledEvents`, `Foundation.Telemetry.Span`, and the test suite) are **still using the Process Dictionary anti-patterns**. They are ready to be refactored and placed behind new feature flags.

### 2. Required Feature Flags (Consolidated from Prompts 2-8)

Based on the migration plan, the following feature flags need to be managed by the `Foundation.FeatureFlags` system:

| Feature Flag | Purpose | Target Module(s) | Relevant Prompt(s) |
| :--- | :--- | :--- | :--- |
| **`use_ets_agent_registry`** | Switches the agent registry from Process Dictionary to an ETS-based implementation. | `lib/foundation/protocols/registry_any.ex`<br>`lib/mabeam/agent_registry_impl.ex` | 2, 3 |
| **`use_logger_error_context`** | Switches error context storage from Process Dictionary to `Logger.metadata`. | `lib/foundation/error_context.ex` | 4 |
| **`use_genserver_telemetry`** | Switches telemetry state management (spans, sampled events) from Process Dictionary to a GenServer/ETS implementation. | `lib/foundation/telemetry/sampled_events.ex`<br>`lib/foundation/telemetry/span.ex` | 5, 6 |
| **`enforce_no_process_dict`** | Enables strict Credo checking to fail the build if any non-whitelisted Process Dictionary usage is found. | `.credo.exs`<br>`lib/foundation/credo_checks/no_process_dict.ex` | 1, 10 |

### 3. Consolidated Implementation Plan

Here is the step-by-step plan to fully implement the feature flag system based on the analysis above.

#### Step A: Extend the `Foundation.FeatureFlags` Module

The existing `lib/foundation/feature_flags.ex` module needs to be updated to be aware of all the new flags.

1.  **Update Default Flags**: Add the new flags to the `@default_flags` map inside `lib/foundation/feature_flags.ex`. This makes them "official" and ensures they have a default value (`false`).

    ```elixir
    # in lib/foundation/feature_flags.ex

    @otp_cleanup_flags %{
      use_ets_agent_registry: false,   # Already exists from Prompt 2
      use_logger_error_context: false, # Add this
      use_genserver_telemetry: false,  # Add this
      enforce_no_process_dict: false   # Add this
    }

    @default_flags Map.merge(@otp_cleanup_flags, %{
      # ... other flags
    })
    ```

2.  **Add to Supervision Tree**: Ensure the `Foundation.FeatureFlags` GenServer is started by the main application supervisor. This should be added to `lib/foundation/services/supervisor.ex` so it starts early and is available to all other services.

    ```elixir
    # in lib/foundation/services/supervisor.ex
    def init(opts) do
      children = [
        # Feature flags service should be one of the first to start
        {Foundation.FeatureFlags, service_opts[:feature_flags] || []},
        # ... other services
      ]
      # ...
    end
    ```

#### Step B: Implement Flag-based Logic in Migrated Code

For each component that is being refactored (Prompts 4, 5, 6), add the `if/else` logic to switch between the legacy and new implementations. The `MABEAM` registry cache can reuse the existing registry flag.

1.  **`lib/mabeam/agent_registry_impl.ex` (Prompt 3)**:
    *   Wrap the cache logic. When the flag is enabled, use the new ETS-based `MABEAM.TableCache`. When disabled, use the old `Process.put/get` logic.
    *   **Flag to use**: `use_ets_agent_registry`.

    ```elixir
    # in lib/mabeam/agent_registry_impl.ex
    def get_tables_from_cache(key) do
      if Foundation.FeatureFlags.enabled?(:use_ets_agent_registry) do
        # New ETS-based cache logic
        MABEAM.TableCache.get(key)
      else
        # Legacy Process Dictionary logic
        case Process.get(cache_key) do
          # ...
        end
      end
    end
    ```

2.  **`lib/foundation/error_context.ex` (Prompt 4)**:
    *   Wrap the `set_context`, `get_context`, and other functions.
    *   **Flag to use**: `use_logger_error_context`.

    ```elixir
    # in lib/foundation/error_context.ex
    def set_context(context) do
      if Foundation.FeatureFlags.enabled?(:use_logger_error_context) do
        Logger.metadata(error_context: context)
      else
        Process.put(:error_context, context)
      end
    end
    ```

3.  **`lib/foundation/telemetry/sampled_events.ex` & `lib/foundation/telemetry/span.ex` (Prompts 5 & 6)**:
    *   Wrap the functions that manage state (e.g., `emit_once_per`, `span`, `start_span`, `end_span`).
    *   **Flag to use**: `use_genserver_telemetry`.

    ```elixir
    # in lib/foundation/telemetry/span.ex
    def start_span(name, metadata) do
      if Foundation.FeatureFlags.enabled?(:use_genserver_telemetry) do
        # New GenServer/ETS implementation for span management
        Foundation.Telemetry.Span.V2.start_span(name, metadata)
      else
        # Legacy Process Dictionary implementation
        stack = Process.get(@span_stack_key, [])
        Process.put(@span_stack_key, [span | stack])
        # ...
      end
    end
    ```

#### Step C: Implement the Enforcement Flag

The `enforce_no_process_dict` flag controls the CI check, not a code path.

1.  **Update `lib/foundation/credo_checks/no_process_dict.ex`**:
    *   Modify the `run/2` function in the custom Credo check.
    *   Before checking a file, it should check the status of the `enforce_no_process_dict` flag.
    *   If the flag is `true`, the `allowed_modules` list should be treated as empty, enforcing the rule everywhere.
    *   If the flag is `false`, it should use the temporary whitelist from the `.credo.exs` file.

    ```elixir
    # in lib/foundation/credo_checks/no_process_dict.ex
    def run(%Credo.SourceFile{} = source_file, params) do
      # ...
      allowed_modules =
        if Foundation.FeatureFlags.enabled?(:enforce_no_process_dict) do
          [] # Strict mode: NO modules are allowed
        else
          # Migration mode: use whitelist from .credo.exs
          params[:allowed_modules] || []
        end
      # ... continue with check logic using the determined allowed_modules list
    end
    ```

#### Step D: Implement Flag-Based Testing

Prompt 8 requires testing both new and legacy code paths. This is a critical part of the consolidation.

1.  **Use ExUnit Tags**: Create tests that explicitly set the feature flag state for their duration.
2.  **Create a Test Helper**: Add a helper in `test/support/feature_flag_helpers.ex` to simplify this.
3.  **Duplicate Critical Tests**: For each migrated component, ensure there is a test suite that runs with the flag enabled and another that runs with it disabled.

    ```elixir
    # in test/support/feature_flag_helpers.ex
    defmodule FeatureFlagHelpers do
      def with_flag(flag, value, fun) do
        original_value = Foundation.FeatureFlags.enabled?(flag)
        Foundation.FeatureFlags.set(flag, value)
        fun.()
      after
        Foundation.FeatureFlags.set(flag, original_value)
      end
    end

    # in a test file, e.g., test/foundation/error_context_test.exs
    import FeatureFlagHelpers

    describe "ErrorContext with legacy implementation" do
      test "sets context using Process.get/put" do
        with_flag :use_logger_error_context, false, fn ->
          Foundation.ErrorContext.set_context(%{user_id: 123})
          assert Process.get(:error_context) == %{user_id: 123}
        end
      end
    end

    describe "ErrorContext with new implementation" do
      @tag feature_flag: :enabled
      test "sets context using Logger.metadata" do
        with_flag :use_logger_error_context, true, fn ->
          # Test Logger.metadata behavior
        end
      end
    end
    ```

By following this consolidated plan, you will successfully implement the feature flag system described in Prompt 8, fully addressing the migration needs of all components from Prompts 2 through 7 and leveraging the existing codebase structures.