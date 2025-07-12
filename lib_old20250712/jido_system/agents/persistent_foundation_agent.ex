defmodule JidoSystem.Agents.PersistentFoundationAgent do
  @moduledoc """
  Enhanced FoundationAgent with automatic state persistence to ETS.

  This agent extends FoundationAgent to provide automatic persistence of
  critical state fields to ETS tables that survive process crashes.

  ## Usage

      defmodule MyAgent do
        use JidoSystem.Agents.PersistentFoundationAgent,
          name: "my_agent",
          description: "Agent with persistent state",
          actions: [MyApp.Actions.ProcessData],
          persistent_fields: [:active_workflows, :task_queue],
          schema: [
            status: [type: :atom, default: :idle],
            active_workflows: [type: :map, default: %{}],
            task_queue: [type: :any, default: :queue.new()]
          ]
      end
  """

  defmacro __using__(opts) do
    # Extract persistent fields configuration and remove from opts
    persistent_fields = Keyword.get(opts, :persistent_fields, [])
    clean_opts = Keyword.delete(opts, :persistent_fields)

    quote location: :keep do
      use JidoSystem.Agents.FoundationAgent, unquote(clean_opts)

      alias JidoSystem.Agents.StatePersistence
      require Logger

      @persistent_fields unquote(persistent_fields)

      # Override mount to restore persisted state
      def mount(agent, opts) do
        # Call parent mount first
        {:ok, agent} = super(agent, opts)

        if @persistent_fields != [] do
          agent_id = agent.id
          Logger.info("Restoring persistent state for agent #{agent_id}")

          # StatePersistence already handles defaults!
          persisted_state = load_persisted_state(agent_id)

          # Simple merge, no complex logic
          updated_agent =
            update_in(
              agent.state,
              &Map.merge(&1, persisted_state)
            )

          # Call hook for custom deserialization
          final_agent =
            if function_exported?(__MODULE__, :on_after_load, 1) do
              __MODULE__.on_after_load(updated_agent)
            else
              updated_agent
            end

          {:ok, final_agent}
        else
          {:ok, agent}
        end
      end

      # New callbacks for custom serialization/deserialization
      @callback on_after_load(agent :: Jido.Agent.t()) :: Jido.Agent.t()
      @callback on_before_save(agent :: Jido.Agent.t()) :: Jido.Agent.t()
      @optional_callbacks [on_after_load: 1, on_before_save: 1]

      # Override on_after_run to persist state after each action
      def on_after_run(agent) do
        result = super(agent)

        # Persist critical state fields after successful run
        if @persistent_fields != [] do
          persist_state(agent)
        end

        result
      end

      # Helper to determine which persistence method to use
      defp load_persisted_state(agent_id) do
        cond do
          __MODULE__ == JidoSystem.Agents.CoordinatorAgent ->
            StatePersistence.load_coordinator_state(agent_id)

          __MODULE__ == JidoSystem.Agents.TaskAgent ->
            StatePersistence.load_task_state(agent_id)

          true ->
            # Generic agent - use coordinator table as default
            StatePersistence.load_coordinator_state(agent_id)
        end
      end

      defp persist_state(agent) do
        # Call hook for custom serialization
        agent_to_save =
          if function_exported?(__MODULE__, :on_before_save, 1) do
            __MODULE__.on_before_save(agent)
          else
            agent
          end

        state_to_persist = Map.take(agent_to_save.state, @persistent_fields)

        cond do
          __MODULE__ == JidoSystem.Agents.CoordinatorAgent ->
            StatePersistence.save_coordinator_state(agent.id, state_to_persist)

          __MODULE__ == JidoSystem.Agents.TaskAgent ->
            StatePersistence.save_task_state(agent.id, state_to_persist)

          true ->
            # Generic agent - use coordinator table as default
            StatePersistence.save_coordinator_state(agent.id, state_to_persist)
        end
      end

      # Allow agents to override these if needed
      defoverridable mount: 2, on_after_run: 1, load_persisted_state: 1, persist_state: 1
    end
  end
end
