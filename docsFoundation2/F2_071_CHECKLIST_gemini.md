Of course. This is a critical step. A well-defined pre-implementation phase ensures we build on a solid, validated foundation, minimizing risks and rework.

Here is a comprehensive list of action items to address before beginning the full implementation of Foundation 2.0.

---

## Foundation 2.0: Pre-Implementation Action Plan

This plan is divided into four key areas: **Foundational Decisions**, **Technical Validation & Prototyping**, **Ecosystem & Dependency Analysis**, and **Project Setup & Governance**.

### I. Foundational Decisions & Strategic Alignment (1-2 Days)

*The goal here is to ensure the entire team is aligned on the core philosophy and scope before any code is written.*

*   **[ ] Action Item: Finalize the "Leaky Abstraction" Philosophy.**
    *   **Task:** Formally review and ratify the "Smart Facades on a Pragmatic Core" and "Leaky Abstractions by Design" principles documented in `F2_050` and `F2_041`.
    *   **Outcome:** A signed-off, one-page document in the project's `docs/philosophy` directory that will serve as the guiding principle for all future design decisions.

*   **[ ] Action Item: Ratify the Three-Tier Configuration Model.**
    *   **Task:** Agree on the final specifications for Mortal, Apprentice, and Wizard modes. Define the exact keywords and behavior for each.
    *   **Outcome:** A clear specification in `TECH_SPECS_DESIGN_DOCS.md` for the configuration system, including examples for each tier.

*   **[ ] Action Item: Define the Minimum Viable Product (MVP) for v2.0.**
    *   **Task:** Review the 12-week implementation plan and decide which features are "must-have" for the initial release versus "nice-to-have" for a subsequent release. (e.g., Is the `Foundation.Optimizer` part of the MVP, or a fast-follow?)
    *   **Outcome:** A prioritized feature list or updated roadmap document marking features as `[MVP]` or `[v2.1]`.

*   **[ ] Action Item: Establish and Agree Upon Success Metrics & SLAs.**
    *   **Task:** Review the SLAs defined in `F2_040_TECH_SPECS_DESIGN_DOCS_claude.md` (e.g., cluster formation time, message latency). Agree on these as the concrete performance targets for the MVP.
    *   **Outcome:** A committed `PERFORMANCE_TARGETS.md` file in the repository.

### II. Technical Validation & Prototyping (3-5 Days)

*The goal is to de-risk the most critical and unproven technical assumptions of the new architecture with small, isolated prototypes.*

*   **[ ] Action Item: Prototype the `Cluster.Strategy.MdnsLite`**.
    *   **Task:** In a new, separate Mix project, create a minimal implementation of the custom `libcluster` strategy using `mdns_lite`.
    *   **Objective:** Prove that we can reliably discover other nodes on a local network, connect to them using `Node.connect/1`, and handle nodes leaving the network.
    *   **Outcome:** A working proof-of-concept demonstrating robust local discovery and connection/disconnection handling.

*   **[ ] Action Item: Validate the Application-Layer Channel (PubSub) Pattern.**
    *   **Task:** Create a small, two-node benchmark project. On one PubSub topic (`:data`), send a continuous stream of large (1MB) messages. Simultaneously, on another topic (`:control`), send small (1KB) messages and measure their round-trip latency.
    *   **Objective:** Quantify the effectiveness of this pattern at mitigating head-of-line blocking. The latency for `:control` messages should remain low (<50ms) even when the `:data` channel is saturated.
    *   **Outcome:** A benchmark script and a brief report confirming this pattern is a viable solution for our needs.

*   **[ ] Action Item: Prototype Horde Singleton Recovery & Consistency Delay.**
    *   **Task:** Create a three-node test cluster. Use the `Foundation.ProcessManager` facade prototype to start a singleton. In a loop, have all three nodes try to look up the singleton. Then, kill the node hosting the singleton.
    *   **Objective:** Measure two key metrics:
        1.  **Time-to-Recovery:** How long does it take for the singleton to be restarted on a new node?
        2.  **Time-to-Consistency:** After recovery, how long does it take for all nodes to be able to successfully look up the *new* PID?
    *   **Outcome:** A test script that gives us real-world numbers for Horde's recovery behavior, which will inform our documentation and facade design (e.g., default timeouts for `wait_for_sync`).

### III. Ecosystem & Dependency Analysis (1-2 Days)

*The goal is to understand the foundation we are building on, ensuring compatibility and avoiding future integration problems.*

*   **[ ] Action Item: Finalize and Lock Core Dependency Versions.**
    *   **Task:** Specify the exact versions of `libcluster`, `Horde`, `phoenix_pubsub`, and `mdns_lite` we will target for the MVP.
    *   **Outcome:** A finalized `mix.exs` `deps` list.

*   **[ ] Action Item: Conduct Compatibility and "Gotcha" Review.**
    *   **Task:** Research the GitHub issues for our core dependencies. Look for known incompatibilities, common operational problems, or tricky configurations when they are used together.
    *   **Outcome:** A `docs/DEPENDENCY_NOTES.md` file capturing any key findings (e.g., "Horde v0.9 has a known issue with X when used with libcluster v3.3").

*   **[ ] Action Item: Research `mdns_lite` Behavior in Common Dev Environments.**
    *   **Task:** Test `mdns_lite` discovery in different development setups:
        *   Host OS (macOS, Linux)
        *   Docker for Mac/Windows (with and without host networking)
        *   WSL2
        *   Remote dev containers (e.g., GitHub Codespaces)
    *   **Objective:** Understand the limitations of our zero-config "Mortal Mode" and document any required setup for these environments.
    *   **Outcome:** A "Developer Environment Setup" guide in the documentation.

### IV. Project Setup & Governance (2-3 Days)

*The goal is to prepare the repository and development workflow so that implementation can proceed efficiently and consistently.*

*   **[ ] Action Item: Establish Project Branching and Versioning Strategy.**
    *   **Task:** Decide on a Git workflow (e.g., GitFlow, Trunk-Based Development). Define how versions will be managed (e.g., Semantic Versioning).
    *   **Outcome:** A `CONTRIBUTING.md` file outlining the development process.

*   **[ ] Action Item: Develop the Multi-Node Test Harness.**
    *   **Task:** Implement the core logic for the `Foundation.ClusterCase` test helper described in the roadmap. This harness should be able to programmatically start and stop multiple nodes in the test environment and facilitate RPC calls between them.
    *   **Outcome:** A working test helper in `test/support/` that can be used by all future integration tests.

*   **[ ] Action Item: Scaffold the Project Directory Structure.**
    *   **Task:** Create the empty files and modules for the core components (`foundation/supervisor.ex`, `foundation/cluster_config.ex`, `foundation/process_manager.ex`, etc.).
    *   **Objective:** Each file should contain the module definition and a `@moduledoc` that clearly states its purpose according to the new architecture. This provides a skeleton for developers to fill in.
    *   **Outcome:** A commit that scaffolds the entire project structure.

*   **[ ] Action Item: Formalize and Commit the Initial Architectural Decision Records (ADRs).**
    *   **Task:** Create a `docs/adr/` directory. Write and commit the first ADRs based on our key decisions.
    *   **Outcome:**
        *   `001-leaky-abstractions-by-design.md`
        *   `002-three-tier-configuration-model.md`
        *   `003-application-layer-channels-with-pubsub.md`
        *   `004-horde-for-process-management.md`

---

### Final Go/No-Go Checklist

**Implementation of Foundation 2.0 core logic should only begin after all the following items are checked:**

- [ ] The "Leaky Abstraction" philosophy is formally documented and agreed upon.
- [ ] The MVP scope is clearly defined.
- [ ] The `MdnsLite` strategy prototype is working.
- [ ] The PubSub channel benchmark has validated our approach to HOL blocking.
- [ ] The Horde recovery prototype has provided real-world timing data.
- [ ] Core dependency versions are locked.
- [ ] The multi-node test harness is functional.
- [ ] The initial ADRs are written and committed to the repository.

Once this checklist is complete, we can proceed with the 12-week implementation plan with high confidence in our architectural direction and technical assumptions.