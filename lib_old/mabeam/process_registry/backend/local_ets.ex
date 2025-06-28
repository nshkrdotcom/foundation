defmodule MABEAM.ProcessRegistry.Backend.LocalETS do
  @moduledoc """
  High-performance ETS-based backend for ProcessRegistry.

  Provides local storage with capability indexing and concurrent access optimization.
  Designed for single-node deployment with future distribution readiness.
  """

  @behaviour MABEAM.ProcessRegistry.Backend

  @default_table_name :mabeam_process_registry
  @capability_index_table :mabeam_capability_index

  # Module-level table tracking for concurrent access
  @table_registry :ets_backend_tables

  @type t :: %{
          main_table: atom(),
          capability_table: atom()
        }

  # Backend API Implementation

  @impl true
  def init(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, @default_table_name)
    capability_table = :"#{table_name}_capabilities"

    # Create table registry if it doesn't exist
    case :ets.info(@table_registry) do
      :undefined ->
        :ets.new(@table_registry, [:named_table, :public, :set])

      _ ->
        :ok
    end

    # Create main agent table if it doesn't exist
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        # Table already exists
        :ok
    end

    # Create capability index table
    case :ets.info(capability_table) do
      :undefined ->
        :ets.new(capability_table, [
          :named_table,
          :public,
          # Multiple agents can have same capability
          :bag,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end

    # Register table names globally
    :ets.insert(@table_registry, {:main_table, table_name})
    :ets.insert(@table_registry, {:capability_table, capability_table})

    {:ok, %{main_table: table_name, capability_table: capability_table}}
  end

  @impl true
  def register_agent(entry) when is_map(entry) do
    main_table = get_main_table()
    capability_table = get_capability_table()

    # Check for existing registration
    case :ets.lookup(main_table, entry.id) do
      [] ->
        # Insert agent entry
        :ets.insert(main_table, {entry.id, entry})

        # Index capabilities
        if entry.config && entry.config.capabilities do
          for capability <- entry.config.capabilities do
            :ets.insert(capability_table, {capability, entry.id})
          end
        end

        :ok

      [_existing] ->
        {:error, :already_registered}
    end
  end

  @impl true
  def update_agent_status(agent_id, status, pid) do
    main_table = get_main_table()

    case :ets.lookup(main_table, agent_id) do
      [{^agent_id, entry}] ->
        now = DateTime.utc_now()

        updated_entry =
          entry
          |> Map.put(:status, status)
          |> Map.put(:pid, pid)
          |> maybe_update_timestamps(status, now)

        :ets.insert(main_table, {agent_id, updated_entry})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def get_agent(agent_id) do
    main_table = get_main_table()

    case :ets.lookup(main_table, agent_id) do
      [{^agent_id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def unregister_agent(agent_id) do
    main_table = get_main_table()
    capability_table = get_capability_table()

    case :ets.lookup(main_table, agent_id) do
      [{^agent_id, entry}] ->
        # Remove from main table
        :ets.delete(main_table, agent_id)

        # Remove from capability index
        if entry.config && entry.config.capabilities do
          for capability <- entry.config.capabilities do
            :ets.delete_object(capability_table, {capability, agent_id})
          end
        end

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_all_agents do
    main_table = get_main_table()

    :ets.tab2list(main_table)
    |> Enum.map(&elem(&1, 1))
  end

  @impl true
  def find_agents_by_capability(required_capabilities) when is_list(required_capabilities) do
    capability_table = get_capability_table()

    if required_capabilities == [] do
      {:ok, []}
    else
      # Get agents for each required capability
      capability_sets =
        for capability <- required_capabilities do
          :ets.lookup(capability_table, capability)
          |> Enum.map(&elem(&1, 1))
          |> MapSet.new()
        end

      # Find intersection (agents that have ALL required capabilities)
      result =
        case capability_sets do
          [] -> MapSet.new()
          [first | rest] -> Enum.reduce(rest, first, &MapSet.intersection/2)
        end

      {:ok, MapSet.to_list(result)}
    end
  end

  @impl true
  def get_agents_by_status(status) do
    main_table = get_main_table()

    agents =
      :ets.tab2list(main_table)
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1.status == status))

    {:ok, agents}
  end

  @impl true
  def cleanup_inactive_agents do
    main_table = get_main_table()
    capability_table = get_capability_table()

    # Find inactive agents (stopped or failed)
    inactive_agents =
      :ets.tab2list(main_table)
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1.status in [:stopped, :failed]))

    # Remove each inactive agent
    for agent <- inactive_agents do
      # Remove from main table
      :ets.delete(main_table, agent.id)

      # Remove from capability index
      if agent.config && agent.config.capabilities do
        for capability <- agent.config.capabilities do
          :ets.delete_object(capability_table, {capability, agent.id})
        end
      end
    end

    {:ok, length(inactive_agents)}
  end

  # Private Helper Functions

  defp get_main_table do
    case :ets.info(@table_registry) do
      :undefined ->
        @default_table_name

      _ ->
        case :ets.lookup(@table_registry, :main_table) do
          [{:main_table, table}] -> table
          [] -> @default_table_name
        end
    end
  end

  defp get_capability_table do
    case :ets.info(@table_registry) do
      :undefined ->
        @capability_index_table

      _ ->
        case :ets.lookup(@table_registry, :capability_table) do
          [{:capability_table, table}] -> table
          [] -> @capability_index_table
        end
    end
  end

  defp maybe_update_timestamps(entry, status, now) do
    case status do
      :running ->
        entry
        |> Map.put(:started_at, now)
        |> Map.put(:stopped_at, nil)

      :stopped ->
        entry
        |> Map.put(:stopped_at, now)

      :failed ->
        entry
        |> Map.put(:stopped_at, now)

      _ ->
        entry
    end
  end
end
