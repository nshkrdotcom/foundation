
# OTP Supervision Audit

This document identifies all instances of unsupervised process creation (`spawn`, `Task.start`) within the core application logic (`lib` directory). Unsupervised processes are a major architectural risk as they are not part of a supervision tree, leading to a lack of fault tolerance and potential for silent failures.

## 1. Audit Findings

The following files contain calls to `spawn`, `spawn_link`, `spawn_monitor`, or `Task.start` that are not linked to a supervisor. These represent critical areas for refactoring to ensure proper OTP compliance and system stability.

*   `lib/mabeam/load_balancer.ex`: 293
*   `lib/mabeam/coordination.ex`: 912
*   `lib/mabeam/comms.ex`: 311
*   `lib/mabeam/agent.ex`: 643, 773
*   `lib/foundation/process_registry.ex`: 757
*   `lib/foundation/application.ex.backup`: 504, 509, 890, 895
*   `lib/foundation/application.ex`: 505, 510, 891, 896
*   `lib/foundation/coordination/primitives.ex`: 650, 678, 687, 737, 743, 788, 794
*   `lib/foundation/beam/processes.ex`: 229

## 2. Analysis and Recommendations

The widespread use of unsupervised `spawn` and `Task.start` indicates a systemic departure from OTP best practices. These calls should be replaced with supervised alternatives.

*   **For long-running processes:** These should be structured as `GenServer`s or other OTP behaviours and started under a supervisor.
*   **For concurrent, short-lived tasks:** These should be managed by a `Task.Supervisor`. This ensures that even temporary tasks are properly monitored and cleaned up.

**Next Steps:**

1.  **Prioritize Refactoring:** The identified files should be prioritized for refactoring. The `foundation` and `mabeam` modules are the most critical.
2.  **Create a `Task.Supervisor`:** A general-purpose `Task.Supervisor` should be added to the main application supervision tree to manage short-lived, concurrent tasks.
3.  **Update Developer Guidelines:** The project's developer guidelines should be updated to explicitly forbid the use of unsupervised `spawn` and `Task.start` in application code.
