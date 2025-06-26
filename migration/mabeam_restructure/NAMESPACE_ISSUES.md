# MABEAM Migration: Namespace Resolution

This document outlines the namespace issues that will need to be resolved after the initial file restructuring for the MABEAM migration.

## Summary of Changes

The migration scripts perform the following actions:

1.  **File Relocation:** `mabeam` source and test files are moved to top-level `lib/` and `test/` directories.
2.  **Module Renaming:** A global find-and-replace changes `Foundation.Mabeam` to `Mabeam`.

## Namespace Issues to Resolve

While the scripts handle the mechanical aspects of the migration, a manual review and refactoring will be required to address the following namespace-related issues:

### 1. Circular Dependencies

**The Problem:** The primary architectural goal is to establish a one-way dependency from `Mabeam` to `Foundation`. The automated renaming does not enforce this. It's highly likely that the `Foundation` codebase now contains references to `Mabeam` modules, creating circular dependencies.

**Action Required:**

*   **Identify Circular Dependencies:** A manual or tool-assisted review of the `lib/foundation` directory is required to find all references to `Mabeam.*` modules.
*   **Refactor:** These dependencies must be removed. This may involve:
    *   **Moving Code:** If a `Foundation` module is tightly coupled with `Mabeam`, it may need to be moved into the `Mabeam` codebase.
    *   **Introducing Callbacks or Protocols:** For loosely coupled dependencies, introducing a callback mechanism or a protocol can invert the dependency.

### 2. Application Supervisor

**The Problem:** The main application supervisor in `lib/foundation/application.ex` will likely have its `Mabeam` child specs broken by the rename.

**Action Required:**

*   **Update Child Specs:** Manually update the supervisor's child list to refer to the new `Mabeam.*` module names.

### 3. Configuration

**The Problem:** Configuration files (e.g., `config/*.exs`) may contain references to `Foundation.Mabeam` modules.

**Action Required:**

*   **Update Configuration:** Review all configuration files and update any references to the new `Mabeam.*` module names.

### 4. Documentation and Tooling

**The Problem:** Documentation, doctests, and tooling configurations may still refer to the old module names and paths.

**Action Required:**

*   **Update Documentation:** Review all `.md` files, `@moduledoc`, and `@doc` annotations.
*   **Update Tooling:** Check `.formatter.exs`, `.dialyzer.ignore.exs`, and any other tooling for outdated paths or module names.

## Next Steps

This document should be used as a guide for the manual refactoring phase of the MABEAM migration. The next step is to execute the migration scripts and then begin the process of resolving the namespace issues outlined above.
