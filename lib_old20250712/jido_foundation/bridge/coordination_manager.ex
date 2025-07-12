defmodule JidoFoundation.Bridge.CoordinationManager do
  @moduledoc """
  Manages MABEAM coordination for Jido agents within Foundation.

  This module provides coordination primitives for multi-agent communication,
  task distribution, and collaborative workflows.
  """

  require Logger

  @doc """
  Coordinates communication between two Jido agents.

  Sends a coordination message from one agent to another through
  the MABEAM coordination system.

  ## Examples

      coordination_message = %{action: :collaborate, task_type: :data_processing}
      CoordinationManager.coordinate_agents(sender_agent, receiver_agent, coordination_message)
  """
  def coordinate_agents(sender_agent, receiver_agent, message) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.coordinate_agents(sender_agent, receiver_agent, message)
  catch
    kind, reason ->
      Logger.warning("Agent coordination failed: #{kind} #{inspect(reason)}")
      {:error, :coordination_failed}
  end

  @doc """
  Distributes a task from a coordinator agent to a worker agent.

  ## Examples

      task = %{id: "task_1", type: :data_analysis, data: %{records: 1000}}
      CoordinationManager.distribute_task(coordinator_agent, worker_agent, task)
  """
  def distribute_task(coordinator_agent, worker_agent, task) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.distribute_task(coordinator_agent, worker_agent, task)
  catch
    kind, reason ->
      Logger.warning("Task distribution failed: #{kind} #{inspect(reason)}")
      {:error, :distribution_failed}
  end

  @doc """
  Delegates a task from a higher-level agent to a lower-level agent in a hierarchy.

  Similar to distribute_task but with hierarchical semantics.

  ## Examples

      task = %{id: "complex_task", type: :analysis, subtasks: [...]}
      CoordinationManager.delegate_task(supervisor_agent, manager_agent, task)
  """
  def delegate_task(delegator_agent, delegate_agent, task) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.delegate_task(delegator_agent, delegate_agent, task)
  catch
    kind, reason ->
      Logger.warning("Task delegation failed: #{kind} #{inspect(reason)}")
      {:error, :delegation_failed}
  end

  @doc """
  Creates a MABEAM coordination context for multiple agents.

  This sets up a coordination environment where multiple agents can
  collaborate on complex tasks.

  ## Examples

      agents = [agent1, agent2, agent3]
      {:ok, coordination_context} = CoordinationManager.create_coordination_context(agents, %{
        coordination_type: :collaborative,
        timeout: 30_000
      })
  """
  def create_coordination_context(agents, opts \\ []) do
    coordination_type = Keyword.get(opts, :coordination_type, :general)
    timeout = Keyword.get(opts, :timeout, 30_000)

    context = %{
      type: coordination_type,
      agents: agents,
      created_at: DateTime.utc_now(),
      timeout: timeout,
      status: :active
    }

    # Use supervised coordination instead of raw send()
    case JidoFoundation.CoordinationManager.create_coordination_context(agents, context) do
      :ok -> {:ok, context}
      {:error, reason} -> {:error, reason}
    end
  end
end
