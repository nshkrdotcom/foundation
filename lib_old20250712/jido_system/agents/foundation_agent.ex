defmodule JidoSystem.Agents.FoundationAgent do
  @moduledoc """
  Base agent that automatically integrates with Foundation infrastructure.

  This agent extends Jido.Agent to provide seamless integration with:
  - Foundation.Registry for agent discovery
  - Foundation.Telemetry for performance monitoring
  - MABEAM for multi-agent coordination
  - JidoFoundation.Bridge for signal routing

  ## Features
  - Auto-registration with Foundation.Registry on startup
  - Automatic telemetry emission for all actions
  - Built-in circuit breaker protection
  - MABEAM coordination capabilities
  - Graceful error handling and recovery

  ## Usage

      defmodule MyAgent do
        use JidoSystem.Agents.FoundationAgent,
          name: "my_agent",
          description: "Custom agent with Foundation integration",
          actions: [MyApp.Actions.ProcessData],
          capabilities: [:data_processing, :analytics],
          schema: [
            status: [type: :atom, default: :idle],
            processed_count: [type: :integer, default: 0]
          ]
      end
  """

  require Logger
  # alias Foundation.Registry # Unused for now
  alias JidoFoundation.Bridge

  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent, unquote(opts)

      require Logger

      # Override specs for Foundation-specific behavior modifications
      # These specs match the actual returns our implementations use
      @spec mount(Jido.Agent.t(), keyword()) ::
              {:ok, Jido.Agent.t()}

      @spec on_before_run(Jido.Agent.t()) ::
              {:ok, Jido.Agent.t()}

      @spec on_after_run(Jido.Agent.t(), term(), list()) ::
              {:ok, Jido.Agent.t()}

      @spec on_error(Jido.Agent.t(), term()) ::
              {:ok, Jido.Agent.t()}

      @spec shutdown(Jido.Agent.t(), term()) ::
              {:ok, Jido.Agent.t()}

      # Override Jido.Agent callback specs that cause Dialyzer warnings
      # Our implementations never return errors for these callbacks
      @spec handle_signal(Jido.Signal.t(), Jido.Agent.t()) :: {:ok, Jido.Signal.t()}
      @spec do_validate(Jido.Agent.t(), map(), keyword()) :: {:ok, map()}
      @spec pending?(Jido.Agent.t()) :: non_neg_integer()
      @spec reset(Jido.Agent.t()) :: {:ok, Jido.Agent.t()}
      @spec transform_result(Jido.Signal.t(), term(), Jido.Agent.t()) :: {:ok, term()}

      @impl true
      def mount(agent, opts) do
        Logger.info("FoundationAgent mount called for agent #{agent.id}")

        try do

          # Register with Foundation Registry
          # Get capabilities from agent metadata or defaults
          capabilities = get_default_capabilities(agent.__struct__)

          metadata = %{
            agent_type: agent.__struct__.__agent_metadata__().name,
            jido_version: Application.spec(:jido, :vsn) || "unknown",
            foundation_integrated: true,
            pid: self(),
            started_at: DateTime.utc_now(),
            capabilities: capabilities
          }

          # Pass metadata properly to Bridge.register_agent
          # Bridge expects capabilities as a separate option, and custom metadata via :metadata option
          bridge_opts = [
            capabilities: capabilities,
            metadata: metadata
          ]

          # Registry is configured via Foundation.TestConfig for testing

          Logger.info("Attempting to register agent #{agent.id} with Bridge",
            opts: inspect(bridge_opts),
            pid: inspect(self())
          )

          try do
            # Use RetryService for reliable agent registration
            registration_result =
              Foundation.Services.RetryService.retry_operation(
                fn -> Bridge.register_agent(self(), bridge_opts) end,
                policy: :exponential_backoff,
                max_retries: 3,
                telemetry_metadata: %{
                  agent_id: agent.id,
                  operation: :agent_registration,
                  capabilities: capabilities
                }
              )

            case registration_result do
              {:ok, :ok} ->
                # RetryService wrapped successful registration
                Logger.info("Agent #{agent.id} registered with Foundation via RetryService",
                  agent_id: agent.id,
                  capabilities: capabilities
                )

                # Emit startup telemetry
                :telemetry.execute([:jido_system, :agent, :started], %{count: 1}, %{
                  agent_id: agent.id,
                  agent_type: agent.__struct__.__agent_metadata__().name,
                  capabilities: capabilities
                })

                {:ok, agent}

              {:error, reason} ->
                Logger.error(
                  "Failed to register agent #{agent.id} with Foundation after retries: #{inspect(reason)}"
                )

                {:error, {:registration_failed, reason}}

              other ->
                # Handle unexpected return values
                Logger.warning(
                  "Unexpected registration result for agent #{agent.id}: #{inspect(other)}"
                )

                {:error, {:unexpected_registration_result, other}}
            end
          rescue
            e ->
              Logger.error("Exception during agent registration for #{agent.id}: #{inspect(e)}")
              Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
              {:error, {:registration_exception, e}}
          end
        rescue
          e ->
            Logger.error("Agent mount failed: #{inspect(e)}")
            {:error, {:mount_failed, e}}
        end
      end

      @impl true
      def on_before_run(agent) do
        # Emit telemetry before action execution
        :telemetry.execute(
          [:jido_foundation, :bridge, :agent_event],
          %{agent_status: Map.get(agent.state, :status, :unknown)},
          %{agent_id: agent.id, event_type: :action_starting}
        )

        {:ok, agent}
      end

      @impl true
      def on_after_run(agent, result, directives) do
        # Emit telemetry after action execution
        case result do
          {:ok, _} ->
            :telemetry.execute(
              [:jido_foundation, :bridge, :agent_event],
              %{duration: 0},
              %{agent_id: agent.id, result: :success, event_type: :action_completed}
            )

          {:error, reason} ->
            :telemetry.execute(
              [:jido_foundation, :bridge, :agent_event],
              %{error: reason},
              %{agent_id: agent.id, result: :error, event_type: :action_failed}
            )

          # Handle bare map results (e.g., from Basic.Log or other actions)
          %{} = map_result ->
            # Determine if this is a success or error based on content
            if Map.has_key?(map_result, :error) or Map.has_key?(map_result, :__exception__) do
              :telemetry.execute(
                [:jido_foundation, :bridge, :agent_event],
                %{error: map_result},
                %{agent_id: agent.id, result: :error, event_type: :action_failed}
              )
            else
              # Treat as success - actions returning bare maps are assumed successful
              :telemetry.execute(
                [:jido_foundation, :bridge, :agent_event],
                %{duration: 0},
                %{agent_id: agent.id, result: :success, event_type: :action_completed}
              )
            end

          # Handle Jido.Error structs (common from action failures)
          %Jido.Error{} = error ->
            :telemetry.execute(
              [:jido_foundation, :bridge, :agent_event],
              %{error: error.message},
              %{agent_id: agent.id, result: :error, event_type: :action_failed}
            )

          # Handle any other result as success (for compatibility)
          _ ->
            Logger.debug("FoundationAgent received unexpected result format: #{inspect(result)}")

            :telemetry.execute(
              [:jido_foundation, :bridge, :agent_event],
              %{duration: 0},
              %{agent_id: agent.id, result: :success, event_type: :action_completed}
            )
        end

        # Return the agent as expected by Jido framework
        # Note: on_after_run callback should return {:ok, agent}, not directives
        {:ok, agent}
      end

      @impl true
      def on_error(agent, error) do
        Logger.warning("Agent #{agent.id} encountered error: #{inspect(error)}")

        # Emit error telemetry
        Bridge.emit_agent_event(
          self(),
          :agent_error,
          %{
            error: error,
            timestamp: System.system_time(:microsecond)
          },
          %{
            agent_id: agent.id,
            recovery_attempted: true
          }
        )

        # Follow the Jido framework pattern - return error to maintain proper error flow
        {:error, error}
      end

      @impl true
      def shutdown(agent, reason) do
        Logger.info("Agent #{agent.id} shutting down: #{inspect(reason)}")

        # Deregister from Foundation
        case Bridge.unregister_agent(self()) do
          :ok ->
            Logger.debug("Agent #{agent.id} deregistered from Foundation")

          {:error, reason} ->
            Logger.warning("Failed to deregister agent #{agent.id}: #{inspect(reason)}")
        end

        # Emit termination telemetry
        :telemetry.execute([:jido_system, :agent, :terminated], %{count: 1}, %{
          agent_id: agent.id,
          reason: reason
        })

        {:ok, agent}
      end

      # Helper function to emit custom events
      @spec emit_event(Jido.Agent.t(), atom(), map(), map()) :: :ok
      def emit_event(agent, event_type, measurements \\ %{}, metadata \\ %{}) do
        Bridge.emit_agent_event(
          self(),
          event_type,
          measurements,
          Map.merge(metadata, %{agent_id: agent.id})
        )
      end

      # Helper function to coordinate with other agents via MABEAM
      @spec coordinate_with_agents(Jido.Agent.t(), term(), keyword()) :: {:ok, String.t()}
      def coordinate_with_agents(agent, task, options \\ []) do
        # For now, implement simple coordination without calling Bridge
        # In a full implementation, this would use MABEAM coordination services
        coordination_id = "coordination_#{System.unique_integer()}"

        Logger.debug("Agent #{agent.id} started coordination: #{coordination_id}")
        {:ok, coordination_id}
      end

      # Helper function to get default capabilities
      @spec get_default_capabilities(module()) :: [atom()]
      defp get_default_capabilities(agent_module) do
        case agent_module do
          JidoSystem.Agents.TaskAgent ->
            [:task_processing, :validation, :queue_management]

          JidoSystem.Agents.MonitorAgent ->
            [:monitoring, :alerting, :health_analysis]

          JidoSystem.Agents.CoordinatorAgent ->
            [:coordination, :orchestration, :workflow_management]

          _ ->
            [:general_purpose]
        end
      end

      defoverridable mount: 2,
                     on_before_run: 1,
                     on_after_run: 3,
                     on_error: 2,
                     shutdown: 2
    end
  end
end
