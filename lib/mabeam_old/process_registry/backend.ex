defmodule MABEAM.ProcessRegistry.Backend do
  @moduledoc """
  Behavior for ProcessRegistry storage backends.

  Defines the interface for pluggable backends that can store and manage
  agent registration information. Backends must be distribution-ready and
  support concurrent access patterns.
  """

  alias MABEAM.Types

  @type agent_entry :: %{
          id: Types.agent_id(),
          config: Types.agent_config(),
          pid: pid() | nil,
          status: :registered | :starting | :running | :stopping | :stopped | :failed,
          started_at: DateTime.t() | nil,
          stopped_at: DateTime.t() | nil,
          metadata: map(),
          node: node()
        }

  @type t :: agent_entry()

  @doc """
  Initialize the backend with the given options.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Register an agent in the backend.
  """
  @callback register_agent(agent_entry()) :: :ok | {:error, reason :: term()}

  @doc """
  Update an agent's status and pid.
  """
  @callback update_agent_status(Types.agent_id(), atom(), pid() | nil) ::
              :ok | {:error, reason :: term()}

  @doc """
  Get agent information by ID.
  """
  @callback get_agent(Types.agent_id()) :: {:ok, agent_entry()} | {:error, :not_found}

  @doc """
  Remove an agent from the registry.
  """
  @callback unregister_agent(Types.agent_id()) :: :ok | {:error, reason :: term()}

  @doc """
  List all registered agents.
  """
  @callback list_all_agents() :: [agent_entry()]

  @doc """
  Find agents by capability.
  """
  @callback find_agents_by_capability([atom()]) ::
              {:ok, [Types.agent_id()]} | {:error, reason :: term()}

  @doc """
  Get agents with a specific status.
  """
  @callback get_agents_by_status(atom()) :: {:ok, [agent_entry()]} | {:error, reason :: term()}

  @doc """
  Cleanup stopped or failed agents.

  Removes agent entries that are in :stopped or :failed status to prevent
  memory growth and maintain registry cleanliness.

  ## Returns

  - `{:ok, cleaned_count}` - Number of agents cleaned up
  - `{:error, reason}` - If cleanup operation fails
  """
  @callback cleanup_inactive_agents() ::
              {:ok, cleaned_count :: non_neg_integer()} | {:error, reason :: term()}
end
