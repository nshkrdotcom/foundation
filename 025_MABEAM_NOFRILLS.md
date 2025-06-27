# MABEAM Restructuring: A "No-Frills" Monorepo Approach

This document outlines a direct, "no-frills" approach to restructuring the Foundation project. The goal is to elevate MABEAM from a sub-module within Foundation to a top-level component in a clean monorepo-style structure.

This plan avoids the overhead of creating separate Hex packages and focuses on achieving a clear architectural separation of concerns within the existing codebase.

---

## The Plan: Step-by-Step

### Step 1: Relocate MABEAM Source Code

The first step is to move the MABEAM code from its current location inside `lib/foundation/` to its own top-level directory in `lib/`.

**Action:**
Execute the following command from the project root:

```bash
mv lib/foundation/mabeam lib/mabeam
```

### Step 2: The Great Renaming (Update Module Names)

With the files moved, all `Foundation.Mabeam` module definitions and references must be updated to the new top-level `Mabeam` namespace.

**Action:**
Perform a project-wide find-and-replace for `Foundation.Mabeam` and replace it with `Mabeam`.

- **Module Definitions:**
  - **Old:** `defmodule Foundation.Mabeam.Agent do`
  - **New:** `defmodule Mabeam.Agent do`

- **Aliases and Callsites:**
  - **Old:** `alias Foundation.Mabeam.Comms`
  - **New:** `alias Mabeam.Comms`

You can use a command-line tool like `sed` or your editor's search and replace feature. Be sure to review the changes carefully.

### Step 3: Update Application Supervision Tree

The main application supervisor likely starts MABEAM-related processes. These references must be updated to reflect the new module names.

**Action:**
1.  Open the main application supervisor file (likely `lib/foundation/application.ex`).
2.  Find the list of children supervised by the application.
3.  Update any `Foundation.Mabeam.*` module names to `Mabeam.*`.

**Example:**

```elixir
# lib/foundation/application.ex

# Old:
children = [
  # ... other children
  Foundation.Mabeam.AgentSupervisor
]

# New:
children = [
  # ... other children
  Mabeam.AgentSupervisor
]
```

### Step 4: Enforce One-Way Dependencies

The core of this refactor is establishing a clear dependency flow. The principle is: **`Mabeam` can depend on `Foundation`, but `Foundation` must NOT depend on `Mabeam`.**

**Action:**

1.  **Review `lib/mabeam/`:** Examine the modules in the new `lib/mabeam` directory. Identify all calls to `Foundation.*` modules. These are now the explicit, allowed dependencies. Based on previous analysis, these will likely be:
    - `Foundation.ProcessRegistry`
    - `Foundation.Telemetry`
    - `Foundation.Coordination`

    For this internal refactor, direct calls like `Foundation.ProcessRegistry.register(...)` are acceptable.

2.  **Review `lib/foundation/`:** Scrutinize all modules remaining in `lib/foundation/`. **There should be zero references to any `Mabeam.*` modules.** Any such reference is a circular dependency and must be refactored out.

### Step 5: Relocate and Update Tests

The test files must mirror the new source code structure.

**Action:**

1.  **Move Test Files:**
    ```bash
    # Create the new directory
    mkdir -p test/mabeam

    # Move the tests
    mv test/foundation/mabeam/* test/mabeam/
    rmdir test/foundation/mabeam
    ```

2.  **Update Test Code:** Perform the same find-and-replace as in Step 2 within the `test/mabeam/` directory to update all module references.

3.  **Verify:** Run the full test suite to ensure all changes are correct and nothing has been broken.
    ```bash
    mix test
    ```

### Step 6: Update Tooling and Documentation

Finally, update project configuration files and documentation to reflect the new structure.

**Action:**

1.  Check `.formatter.exs` for any path-specific rules that need to be updated.
2.  Check `.dialyzer.ignore.exs` for any warnings related to the old module names or paths.
3.  Update any internal documentation (`.md` files), `@moduledoc`, and `@doc` annotations that refer to the old `Foundation.Mabeam` structure.

---

## Summary of New Structure

After completing these steps, the relevant parts of your project will look like this:

```
.
├── lib/
│   ├── foundation/
│   │   ├── application.ex
│   │   └── ... (core foundation files)
│   └── mabeam/
│       ├── agent.ex
│       └── ... (core mabeam files)
├── test/
│   ├── foundation/
│   │   └── ... (foundation tests)
│   └── mabeam/
│       ├── agent_test.exs
│       └── ... (mabeam tests)
└── mix.exs
```

This structure achieves a clean separation of `Mabeam` as a distinct component within the project, improving the architecture and setting a clear foundation for future development.
