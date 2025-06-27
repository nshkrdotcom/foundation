# Analysis of `foundation` to `mabeam` Dependencies

This document analyzes the dependencies from the `foundation` library to the `mabeam` library. The goal is to identify and recommend solutions for dependencies that are undesirable, maintaining a clean separation of concerns where `foundation` is the core framework and `mabeam` is a feature built on top of it.

## Summary of Findings

The analysis of `grep -ir mabeam lib/foundation/*` reveals several files with references to `mabeam`.

1.  **`lib/foundation/application.ex`**: Contains the most significant and problematic dependencies. It has leftover logic for a `:mabeam` application startup phase, even though the service definitions have been moved to a separate `mabeam` application. This is a code smell from an incomplete refactoring.

2.  **`lib/foundation/coordination/primitives.ex`**: The module documentation mentions `MABEAM` as a consumer of these primitives. This is an acceptable conceptual dependency.

3.  **`lib/foundation/process_registry.ex`**: The type definition for service names includes a `{:mabeam, atom()}` variant, and an example mentions a `:mabeam_agent`. This is acceptable loose coupling for a generic service registry.

4.  **`lib/foundation/services/service_behaviour.ex`**: The module documentation mentions preparing for `MABEAM` coordination. This is an acceptable conceptual dependency.

5.  **`lib/foundation/types/error.ex`**: A comment mentions enhanced error fields for `MABEAM`. The fields are generic for distributed systems, so this is not a hard dependency.

The primary issue is the leftover application logic in `Foundation.Application`. Other references are acceptable for a core framework designed to be extended.

## Detailed Analysis and Recommendations

### 1. `lib/foundation/application.ex`

*   **Finding**: This file has multiple references to a `:mabeam` startup phase.
    *   The `@type startup_phase` includes `:mabeam`.
    *   `@service_definitions` for `mabeam` are commented out with a note that they have been moved.
    *   `build_supervision_tree` still calls `build_phase_children(:mabeam)`.
    *   `perform_graceful_shutdown` and `group_services_by_phase` still include `:mabeam` in their phase lists.
*   **Impact**: While this may not cause a runtime error (as no services are defined in the `:mabeam` phase), it makes `Foundation.Application` aware of a specific feature module (`mabeam`), which is a violation of dependency direction. It's an incomplete refactoring.
*   **Recommendation**: Remove all logic related to the `:mabeam` phase from `Foundation.Application`.
    *   Remove `:mabeam` from the `@type startup_phase` definition.
    *   In `build_supervision_tree`, remove the `mabeam_children` variable and its inclusion in the final children list.
    *   In `perform_graceful_shutdown`, remove `:mabeam` from the `shutdown_phases` list.
    *   In `group_services_by_phase`, remove `:mabeam` from the `phases` list.
    *   The `MABEAM` application should be managed by a higher-level supervisor that composes `Foundation` and `MABEAM`.

### 2. `lib/foundation/coordination/primitives.ex`

*   **Finding**: The module documentation states that it provides primitives for `MABEAM`.
*   **Impact**: This is a documentation-level reference. It explains the motivation and intended use of the module. It does not create a code-level dependency.
*   **Recommendation**: No action required. This is an acceptable way to document the relationship between a core framework and its extensions.

### 3. `lib/foundation/process_registry.ex`

*   **Finding**:
    1.  The `@type service_name` includes `{:mabeam, atom()}`.
    2.  A documentation example uses a `:mabeam_agent`.
*   **Impact**: These are forms of very loose coupling.
    1.  Allowing a `{:mabeam, atom()}` service name makes the registry more flexible and allows `mabeam` to namespace its services without `foundation` needing to know about the `mabeam` modules themselves.
    2.  The example is for documentation purposes.
*   **Recommendation**: No action required. The process registry is behaving as a generic service.

### 4. `lib/foundation/services/service_behaviour.ex`

*   **Finding**: The module documentation states it prepares for `MABEAM` multi-agent coordination.
*   **Impact**: Similar to `primitives.ex`, this is a documentation-level reference.
*   **Recommendation**: No action required.

### 5. `lib/foundation/types/error.ex`

*   **Finding**: A comment mentions that some fields are for `MABEAM`.
*   **Impact**: This is only a comment. The fields themselves are generic and useful for any distributed system.
*   **Recommendation**: No action required.

## Conclusion

The `foundation` library is mostly well-decoupled from `mabeam`. The only necessary change is to complete the refactoring in `lib/foundation/application.ex` to remove the vestigial `:mabeam` startup phase logic. The other references are acceptable and reflect `foundation`'s role as a framework for modules like `mabeam`.
