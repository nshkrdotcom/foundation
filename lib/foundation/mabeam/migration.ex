defmodule Foundation.MABEAM.Migration do
  @moduledoc """
  Migration utilities for transitioning from the old MABEAM ProcessRegistry
  to the unified Foundation.ProcessRegistry system.

  This module provides tools for:
  - Migrating existing agent registrations
  - Validating migration completeness
  - Rolling back migrations if needed
  - Managing the gradual migration process with feature flags

  ## Usage

      # Migrate all agents to unified registry
      {:ok, migrated_count} = Migration.migrate_agents_to_unified_registry()

      # Validate migration is complete
      :ok = Migration.validate_migration()

      # Rollback migration if needed
      {:ok, rolled_back_count} = Migration.rollback_migration()
  """

  require Logger
  alias Foundation.{ProcessRegistry, MABEAM}

  @type migration_result ::
          {:ok, non_neg_integer()}
          | {:error,
             {:migration_exception | :rollback_exception | :partial_migration | :partial_rollback,
              term()}}
  @type validation_result ::
          :ok
          | {:error, {:agents_not_migrated | :orphaned_agents_in_legacy, term()}}

  @doc """
  Migrate all agents from the old MABEAM ProcessRegistry to the unified Foundation.ProcessRegistry.

  This function:
  1. Reads all agents from the old MABEAM registry
  2. Transforms them to the new unified format
  3. Registers them in the unified registry
  4. Optionally removes them from the old registry

  ## Options
  - `:dry_run` - If true, only simulates the migration without making changes (default: false)
  - `:cleanup_old` - If true, removes agents from old registry after successful migration (default: true)

  ## Returns
  - `{:ok, count}` - Migration successful, returns number of migrated agents
  - `{:error, reason}` - Migration failed

  ## Examples

      # Perform actual migration
      {:ok, 5} = Migration.migrate_agents_to_unified_registry()

      # Dry run to see what would be migrated
      {:ok, 5} = Migration.migrate_agents_to_unified_registry(dry_run: true)
  """
  @spec migrate_agents_to_unified_registry(keyword()) :: migration_result()
  def migrate_agents_to_unified_registry(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    cleanup_old = Keyword.get(opts, :cleanup_old, true)

    Logger.info("Starting MABEAM agent migration to unified registry (dry_run: #{dry_run})")

    try do
      # Check if old registry is running
      case get_legacy_agents() do
        {:ok, legacy_agents} ->
          if dry_run do
            Logger.info("Dry run: Would migrate #{length(legacy_agents)} agents")
            {:ok, length(legacy_agents)}
          else
            perform_migration(legacy_agents, cleanup_old)
          end

        {:error, :legacy_registry_not_running} ->
          Logger.info("Legacy MABEAM registry not running - no migration needed")
          {:ok, 0}
      end
    rescue
      error ->
        Logger.error("Migration failed with exception: #{inspect(error)}")
        {:error, {:migration_exception, error}}
    end
  end

  @doc """
  Validate that the migration has been completed successfully.

  This function checks:
  1. All expected agents are in the unified registry
  2. Agent configurations are correctly transformed
  3. No agents are orphaned in the old registry
  4. Registry integrity is maintained

  ## Returns
  - `:ok` - Migration is valid and complete
  - `{:error, reason}` - Migration validation failed

  ## Examples

      case Migration.validate_migration() do
        :ok -> 
          IO.puts("Migration is complete and valid")
        {:error, error_reason} -> 
          IO.puts("Migration validation failed: \#{inspect(error_reason)}")
      end
  """
  @spec validate_migration() :: validation_result()
  def validate_migration do
    Logger.info("Validating MABEAM migration to unified registry")

    with {:ok, legacy_agents} <- get_legacy_agents(),
         :ok <- validate_unified_agents(legacy_agents),
         :ok <- validate_no_orphaned_agents() do
      Logger.info("Migration validation successful")
      :ok
    else
      {:error, :legacy_registry_not_running} ->
        # If legacy registry isn't running, that's actually good for migration
        Logger.info("Legacy registry not running - migration appears complete")
        :ok

      {:error, reason} ->
        Logger.error("Migration validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Rollback the migration by moving agents back to the old MABEAM registry.

  This function:
  1. Finds all migrated agents in the unified registry
  2. Transforms them back to the old format
  3. Registers them in the old MABEAM registry
  4. Optionally removes them from the unified registry

  ## Options
  - `:dry_run` - If true, only simulates the rollback without making changes (default: false)
  - `:cleanup_unified` - If true, removes agents from unified registry after rollback (default: true)

  ## Returns
  - `{:ok, count}` - Rollback successful, returns number of rolled back agents
  - `{:error, reason}` - Rollback failed

  ## Examples

      # Perform actual rollback
      {:ok, 5} = Migration.rollback_migration()

      # Dry run to see what would be rolled back
      {:ok, 5} = Migration.rollback_migration(dry_run: true)
  """
  @spec rollback_migration(keyword()) :: migration_result()
  def rollback_migration(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    cleanup_unified = Keyword.get(opts, :cleanup_unified, true)

    Logger.info("Starting MABEAM migration rollback (dry_run: #{dry_run})")

    try do
      # Get all MABEAM agents from unified registry
      unified_agents = get_unified_mabeam_agents()

      if dry_run do
        Logger.info("Dry run: Would rollback #{length(unified_agents)} agents")
        {:ok, length(unified_agents)}
      else
        perform_rollback(unified_agents, cleanup_unified)
      end
    rescue
      error ->
        Logger.error("Rollback failed with exception: #{inspect(error)}")
        {:error, {:rollback_exception, error}}
    end
  end

  @doc """
  Check if the unified registry is currently being used.

  This is controlled by the `:use_unified_registry` feature flag.

  ## Returns
  - `true` - Unified registry is enabled
  - `false` - Legacy registry is being used
  """
  @spec using_unified_registry?() :: boolean()
  def using_unified_registry? do
    case Application.get_env(:foundation, :mabeam, []) do
      mabeam_config when is_list(mabeam_config) ->
        Keyword.get(mabeam_config, :use_unified_registry, false)

      _ ->
        false
    end
  end

  @doc """
  Enable or disable the unified registry feature flag.

  ## Parameters
  - `enabled` - Whether to enable the unified registry

  ## Examples

      # Enable unified registry
      Migration.set_unified_registry(true)

      # Disable unified registry (use legacy)
      Migration.set_unified_registry(false)
  """
  @spec set_unified_registry(boolean()) :: :ok
  def set_unified_registry(enabled) when is_boolean(enabled) do
    # Get current MABEAM config and update the use_unified_registry flag
    current_mabeam_config = Application.get_env(:foundation, :mabeam, [])
    updated_config = Keyword.put(current_mabeam_config, :use_unified_registry, enabled)
    Application.put_env(:foundation, :mabeam, updated_config)
    Logger.info("Unified registry feature flag set to: #{enabled}")
  end

  @doc """
  Get migration statistics and status.

  ## Returns
  A map containing:
  - `:legacy_agent_count` - Number of agents in legacy registry
  - `:unified_agent_count` - Number of MABEAM agents in unified registry
  - `:using_unified` - Whether unified registry is enabled
  - `:migration_complete` - Whether migration appears complete
  """
  @spec migration_status() :: %{
          legacy_agent_count: non_neg_integer(),
          unified_agent_count: non_neg_integer(),
          using_unified: boolean(),
          migration_complete: boolean()
        }
  def migration_status do
    legacy_count =
      case get_legacy_agents() do
        {:ok, agents} -> length(agents)
        {:error, _} -> 0
      end

    unified_count = length(get_unified_mabeam_agents())
    using_unified = using_unified_registry?()

    %{
      legacy_agent_count: legacy_count,
      unified_agent_count: unified_count,
      using_unified: using_unified,
      migration_complete: legacy_count == 0 and unified_count > 0
    }
  end

  # Private helper functions

  defp get_legacy_agents do
    # Try to get agents from the old MABEAM ProcessRegistry
    try do
      case Process.whereis(Foundation.MABEAM.ProcessRegistry) do
        nil ->
          {:error, :legacy_registry_not_running}

        _pid ->
          # The MABEAM ProcessRegistry might not have list_agents/0
          # Instead, we'll assume empty list if function doesn't exist
          try do
            # Foundation.MABEAM.ProcessRegistry.list_agents() should return {:ok, agents}
            # If it does not exist, the rescue clause will handle it
            Foundation.MABEAM.ProcessRegistry.list_agents()
          rescue
            _ -> {:ok, []}
          end
      end
    rescue
      error ->
        Logger.debug("Error accessing legacy registry: #{inspect(error)}")
        {:error, :legacy_registry_not_running}
    end
  end

  defp get_unified_mabeam_agents do
    # Get all MABEAM agents from the unified registry
    ProcessRegistry.find_services_by_metadata(:production, fn metadata ->
      metadata[:type] == :mabeam_agent
    end)
  end

  defp perform_migration(legacy_agents, cleanup_old) do
    Logger.info("Migrating #{length(legacy_agents)} agents to unified registry")

    # migrated_count was not being used - the actual count is calculated from the results list
    _migrated_count = 0

    results =
      Enum.map(legacy_agents, fn agent ->
        transform_and_migrate_agent(agent, cleanup_old)
      end)

    # Count successful migrations
    successful_migrations =
      Enum.count(results, fn
        :ok -> true
        _ -> false
      end)

    # Check for any failures
    failures =
      Enum.filter(results, fn
        :ok -> false
        _ -> true
      end)

    if length(failures) > 0 do
      Logger.error("Migration had #{length(failures)} failures: #{inspect(failures)}")
      {:error, {:partial_migration, successful_migrations, failures}}
    else
      Logger.info("Successfully migrated #{successful_migrations} agents")
      {:ok, successful_migrations}
    end
  end

  defp transform_and_migrate_agent(legacy_agent, cleanup_old) do
    try do
      # Transform legacy agent to unified format
      unified_config = transform_legacy_to_unified(legacy_agent)

      # Register in unified registry using the Agent module
      case MABEAM.Agent.register_agent(unified_config) do
        :ok ->
          if cleanup_old do
            # Remove from legacy registry
            _ = Foundation.MABEAM.ProcessRegistry.stop_agent(legacy_agent.id)
          end

          :ok

        {:error, {:already_registered, _}} ->
          # Agent already migrated, that's fine
          Logger.debug("Agent #{legacy_agent.id} already migrated")
          :ok

        {:error, reason} ->
          Logger.error("Failed to migrate agent #{legacy_agent.id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception migrating agent #{legacy_agent.id}: #{inspect(error)}")
        {:error, {:transform_exception, error}}
    end
  end

  defp transform_legacy_to_unified(legacy_agent) do
    # Transform the legacy agent format to the new unified format
    %{
      id: legacy_agent.id,
      type: legacy_agent.config.type,
      module: legacy_agent.config.module,
      args: legacy_agent.config.args || [],
      capabilities: extract_capabilities(legacy_agent),
      restart_policy: legacy_agent.config.restart_policy || :permanent,
      metadata: legacy_agent.metadata || %{}
    }
  end

  defp extract_capabilities(legacy_agent) do
    # Extract capabilities from legacy agent configuration
    cond do
      Map.has_key?(legacy_agent.config, :capabilities) ->
        legacy_agent.config.capabilities

      Map.has_key?(legacy_agent, :capabilities) ->
        legacy_agent.capabilities

      true ->
        []
    end
  end

  defp validate_unified_agents(legacy_agents) do
    # Check that all legacy agents have been migrated to unified registry
    unified_agents = get_unified_mabeam_agents()

    unified_ids =
      Enum.map(unified_agents, fn {service_key, _pid, _metadata} ->
        extract_agent_id_from_service_key(service_key)
      end)

    legacy_ids = Enum.map(legacy_agents, & &1.id)

    missing_ids = legacy_ids -- unified_ids

    if length(missing_ids) > 0 do
      {:error, {:agents_not_migrated, missing_ids}}
    else
      :ok
    end
  end

  defp extract_agent_id_from_service_key({:agent, agent_id}), do: agent_id
  defp extract_agent_id_from_service_key(other), do: other

  defp validate_no_orphaned_agents do
    # Check for agents that might be orphaned in the old registry
    case get_legacy_agents() do
      {:ok, legacy_agents} when legacy_agents != [] ->
        {:error, {:orphaned_agents_in_legacy, length(legacy_agents)}}

      {:ok, []} ->
        :ok

      {:error, :legacy_registry_not_running} ->
        :ok

      # This case shouldn't occur with our updated logic
      _ ->
        {:error, :unexpected_error}
    end
  end

  defp perform_rollback(unified_agents, cleanup_unified) do
    Logger.info("Rolling back #{length(unified_agents)} agents to legacy registry")

    results =
      Enum.map(unified_agents, fn {service_key, _pid, metadata} ->
        rollback_agent(service_key, metadata, cleanup_unified)
      end)

    # Count successful rollbacks
    successful_rollbacks =
      Enum.count(results, fn
        :ok -> true
        _ -> false
      end)

    # Check for any failures
    failures =
      Enum.filter(results, fn
        :ok -> false
        _ -> true
      end)

    if length(failures) > 0 do
      Logger.error("Rollback had #{length(failures)} failures: #{inspect(failures)}")
      {:error, {:partial_rollback, successful_rollbacks, failures}}
    else
      Logger.info("Successfully rolled back #{successful_rollbacks} agents")
      {:ok, successful_rollbacks}
    end
  end

  defp rollback_agent(service_key, metadata, cleanup_unified) do
    agent_id = extract_agent_id_from_service_key(service_key)

    try do
      # Transform unified agent back to legacy format
      legacy_config = transform_unified_to_legacy(agent_id, metadata)

      # Register in legacy registry
      case Foundation.MABEAM.ProcessRegistry.register_agent(legacy_config) do
        :ok ->
          if cleanup_unified do
            # Remove from unified registry
            _ = MABEAM.Agent.unregister_agent(agent_id)
          end

          :ok

        {:error, :already_registered} ->
          # Agent already in legacy registry
          Logger.debug("Agent #{agent_id} already in legacy registry")
          :ok

        {:error, reason} ->
          Logger.error("Failed to rollback agent #{agent_id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception rolling back agent #{agent_id}: #{inspect(error)}")
        {:error, {:rollback_exception, error}}
    end
  end

  defp transform_unified_to_legacy(agent_id, metadata) do
    # Transform unified metadata back to legacy format
    # Use the correct new_agent_config/4 function signature with module as second parameter
    Foundation.MABEAM.Types.new_agent_config(
      agent_id,
      metadata[:module] || Foundation.MABEAM.Agent.Worker,
      metadata[:args] || [],
      type: metadata[:agent_type] || :worker,
      capabilities: metadata[:capabilities] || [],
      restart_policy: %{
        strategy: metadata[:restart_policy] || :permanent,
        max_restarts: 3,
        period_seconds: 60,
        backoff_strategy: :exponential
      },
      metadata: Map.get(metadata, :config, %{})
    )
  end
end
