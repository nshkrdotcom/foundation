### Priority: Explicit Failure for Placeholder Modules (e.g., `process_registry/backend/horde.ex`)

This document elaborates on the critical importance of ensuring that placeholder modules, particularly `process_registry/backend/horde.ex`, explicitly fail if their intended dependencies or implementations are not present. This is not merely a "code smell" but a significant risk to development, debugging, and system integrity in a distributed environment.

#### The Problem: Silent Misdirection and Hidden Complexity

The current state of `process_registry/backend/horde.ex` (as observed in `GEMINI_REVIEW_20250625_1630_08_GRACEFUL_FUTURE.md`) is that it "simply delegates to the ETS backend." While this might seem harmless as a temporary measure, it creates a dangerous scenario:

1.  **False Sense of Security:** A developer configuring the system for distributed operation might select the `Horde` backend, assuming it will provide distributed behavior. Because the module silently falls back to `ETS`, the system will *appear* to function, but it will not be distributed. This can lead to significant confusion and wasted debugging time when distributed features (like cross-node process discovery) fail to materialize.
2.  **Hidden Bottlenecks:** If the system is deployed with the `Horde` backend configured but silently using `ETS`, all `ProcessRegistry` operations will remain local to a single node. This negates the benefits of a distributed architecture and can lead to unexpected performance bottlenecks and single points of failure in production, even if `Horde` is theoretically "enabled."
3.  **Delayed Discovery of Missing Dependencies:** The lack of an explicit error means that the `Horde` library (or any other intended dependency for a placeholder) might not be added to `mix.exs` or installed until much later in the development cycle, potentially during deployment or integration testing. Discovering such fundamental issues late is always more costly and time-consuming to fix.

#### Why This is a High Priority

This issue directly impacts the successful transition to a distributed architecture, which was identified as a primary architectural hurdle in `GEMINI_REVIEW_20250625_1630_02_SINGLETON_TO_DISTRO.md`. The `ProcessRegistry`'s ability to correctly utilize a distributed backend (like `Horde`) is foundational to distributing services like `Foundation.MABEAM.Coordination` and `Foundation.MABEAM.Economics`. A silent failure here undermines the entire distributed strategy.

An explicit failure mechanism ensures:

*   **Early Feedback:** Developers are immediately alerted if a required dependency or an unimplemented backend is being used incorrectly.
*   **Clear Intent:** The system's behavior is unambiguous. If you configure `Horde`, you either get `Horde` or a clear error message explaining why not.
*   **Reduced Debugging Time:** Eliminates the possibility of spending hours trying to figure out why distributed features aren't working when the underlying backend isn't actually distributed.

#### Recommended Solution

The module should be made to fail explicitly if used without the `Horde` library or its proper implementation. This can be achieved by raising an error in its `init/1` function.

```elixir
# In lib/foundation/process_registry/backend/horde.ex

defmodule Foundation.ProcessRegistry.Backend.Horde do
  @moduledoc """
  Horde backend for the ProcessRegistry.

  This module is intended to provide a distributed process registry using the Horde library.
  If Horde is not available or this backend is not fully implemented, it will raise an error
  to prevent silent fallback to a non-distributed behavior.
  """

  @behaviour Foundation.ProcessRegistry.Backend

  @impl Foundation.ProcessRegistry.Backend
  def init(opts) do
    # Check if Horde is loaded. If not, it means the dependency is missing or not started.
    if Code.ensure_loaded?(Horde) do
      # TODO: Implement the actual Horde.Registry initialization here.
      # For now, raise an error to prevent silent delegation to ETS.
      raise "Foundation.ProcessRegistry.Backend.Horde is configured but not yet fully implemented. Please implement the Horde backend or use a different backend."
    else
      # This error indicates that the :horde dependency is missing from mix.exs
      raise "The :horde dependency is not available. Please add it to your mix.exs file to use the Horde backend for distributed process registration."
    end
  end

  @impl Foundation.ProcessRegistry.Backend
  def register(name, pid, opts), do: raise("Horde backend not implemented: register/3")
  @impl Foundation.ProcessRegistry.Backend
  def unregister(name), do: raise("Horde backend not implemented: unregister/1")
  @impl Foundation.ProcessRegistry.Backend
  def lookup(name), do: raise("Horde backend not implemented: lookup/1")
  @impl Foundation.ProcessRegistry.Backend
  def whereis(name), do: raise("Horde backend not implemented: whereis/1")
  @impl Foundation.ProcessRegistry.Backend
  def registered_names(), do: raise("Horde backend not implemented: registered_names/0")
end
```

This change ensures that any attempt to use the `Horde` backend before it's fully ready or correctly configured will result in an immediate, clear, and actionable error, guiding the developer towards the correct setup for distributed operation. This is a crucial step in maintaining the integrity and predictability of the system as it evolves.