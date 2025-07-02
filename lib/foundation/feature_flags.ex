defmodule Foundation.FeatureFlags do
  @moduledoc """
  Feature flags system for managing gradual rollout of changes.

  This module provides a centralized way to manage feature flags across the Foundation
  system, enabling safe rollout of potentially risky changes.
  """

  use GenServer
  require Logger

  @table_name :foundation_feature_flags

  # Default feature flags for OTP cleanup
  @otp_cleanup_flags %{
    use_ets_agent_registry: false,
    use_logger_error_context: false,
    use_genserver_telemetry: false,
    use_genserver_span_management: false,
    use_ets_sampled_events: false,
    enforce_no_process_dict: false,
    enable_migration_monitoring: false
  }

  # All available feature flags
  @default_flags Map.merge(
                   @otp_cleanup_flags,
                   %{
                     # Add other feature flags here as needed
                   }
                 )

  # Public API

  @doc """
  Starts the feature flags GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks if a feature flag is enabled.

  ## Examples

      iex> Foundation.FeatureFlags.enabled?(:use_ets_agent_registry)
      false
      
      iex> Foundation.FeatureFlags.enable(:use_ets_agent_registry)
      :ok
      iex> Foundation.FeatureFlags.enabled?(:use_ets_agent_registry)
      true
  """
  def enabled?(flag_name) when is_atom(flag_name) do
    ensure_table_exists()

    case :ets.lookup(@table_name, flag_name) do
      [{^flag_name, value}] -> value
      [] -> Map.get(@default_flags, flag_name, false)
    end
  end

  @doc """
  Enables a feature flag.
  """
  def enable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:set_flag, flag_name, true})
  end

  @doc """
  Disables a feature flag.
  """
  def disable(flag_name) when is_atom(flag_name) do
    GenServer.call(__MODULE__, {:set_flag, flag_name, false})
  end

  @doc """
  Sets a feature flag to a specific value.
  """
  def set(flag_name, value) when is_atom(flag_name) and is_boolean(value) do
    GenServer.call(__MODULE__, {:set_flag, flag_name, value})
  end

  @doc """
  Sets a feature flag to a percentage rollout (0-100).
  """
  def set_percentage(flag_name, percentage)
      when is_atom(flag_name) and is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(__MODULE__, {:set_flag, flag_name, percentage})
  end

  @doc """
  Checks if a feature flag is enabled for a specific ID (for gradual rollout).
  """
  def enabled_for_id?(flag_name, id) when is_atom(flag_name) do
    ensure_table_exists()

    case :ets.lookup(@table_name, flag_name) do
      [{^flag_name, true}] ->
        true

      [{^flag_name, false}] ->
        false

      [{^flag_name, percentage}] when is_integer(percentage) ->
        # Consistent hashing for gradual rollout
        hash = :erlang.phash2({flag_name, id}, 100)
        hash < percentage

      [] ->
        Map.get(@default_flags, flag_name, false)
    end
  end

  @doc """
  Lists all feature flags and their current values.
  """
  def list_all do
    ensure_table_exists()

    # Get all flags from ETS
    ets_flags = :ets.tab2list(@table_name) |> Map.new()

    # Merge with defaults (ETS values take precedence)
    Map.merge(@default_flags, ets_flags)
  end

  @doc """
  Resets all feature flags to their default values.
  """
  def reset_all do
    GenServer.call(__MODULE__, :reset_all)
  end

  @doc """
  Loads feature flags from configuration.
  """
  def load_from_config do
    GenServer.call(__MODULE__, :load_from_config)
  end

  # Migration Control Functions

  @doc """
  Enables OTP cleanup flags in stages for safe migration.
  """
  def enable_otp_cleanup_stage(stage) when stage in 1..4 do
    GenServer.call(__MODULE__, {:enable_migration_stage, stage})
  end

  @doc """
  Rolls back to a previous migration stage.
  """
  def rollback_migration_stage(stage) when stage in 1..4 do
    GenServer.call(__MODULE__, {:rollback_migration_stage, stage})
  end

  @doc """
  Gets the current migration status.
  """
  def migration_status do
    GenServer.call(__MODULE__, :migration_status)
  end

  @doc """
  Emergency rollback - disables all OTP cleanup flags.
  """
  def emergency_rollback(reason \\ "Emergency rollback") do
    GenServer.call(__MODULE__, {:emergency_rollback, reason})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for feature flags
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true}
    ])

    # Load initial flags from configuration
    load_initial_flags()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_flag, flag_name, value}, _from, state) do
    if Map.has_key?(@default_flags, flag_name) do
      # Ensure table exists before inserting
      ensure_table_exists_in_server()

      :ets.insert(@table_name, {flag_name, value})
      Logger.info("Feature flag #{flag_name} set to #{value}")

      # Emit telemetry for monitoring
      :telemetry.execute(
        [:foundation, :feature_flag, :changed],
        %{count: 1},
        %{flag: flag_name, value: value, timestamp: System.monotonic_time()}
      )

      {:reply, :ok, state}
    else
      {:reply, {:error, :unknown_flag}, state}
    end
  end

  @impl true
  def handle_call(:reset_all, _from, state) do
    :ets.delete_all_objects(@table_name)
    Logger.info("All feature flags reset to defaults")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:load_from_config, _from, state) do
    load_initial_flags()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:enable_migration_stage, stage}, _from, state) do
    Logger.info("Enabling OTP cleanup migration stage #{stage}")

    case stage do
      1 ->
        # Stage 1: Registry migration
        :ets.insert(@table_name, {:use_ets_agent_registry, true})
        :ets.insert(@table_name, {:enable_migration_monitoring, true})

      2 ->
        # Stage 2: Error context migration
        :ets.insert(@table_name, {:use_logger_error_context, true})

      3 ->
        # Stage 3: Telemetry migration
        :ets.insert(@table_name, {:use_genserver_telemetry, true})
        :ets.insert(@table_name, {:use_genserver_span_management, true})
        :ets.insert(@table_name, {:use_ets_sampled_events, true})

      4 ->
        # Stage 4: Enforcement
        :ets.insert(@table_name, {:enforce_no_process_dict, true})
    end

    # Store migration status
    :ets.insert(@table_name, {:migration_stage, stage})
    :ets.insert(@table_name, {:migration_timestamp, System.monotonic_time()})

    :telemetry.execute(
      [:foundation, :migration, :stage_enabled],
      %{stage: stage},
      %{timestamp: System.monotonic_time()}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:rollback_migration_stage, target_stage}, _from, state) do
    current_stage =
      case :ets.lookup(@table_name, :migration_stage) do
        [{:migration_stage, stage}] -> stage
        [] -> 0
      end

    if target_stage < current_stage do
      Logger.warning("Rolling back migration from stage #{current_stage} to #{target_stage}")

      # Disable flags based on target stage
      case target_stage do
        0 ->
          # Rollback everything
          Enum.each(Map.keys(@otp_cleanup_flags), fn flag ->
            :ets.insert(@table_name, {flag, false})
          end)

        1 ->
          # Keep only registry changes - ensure stage 1 flags are enabled
          :ets.insert(@table_name, {:use_ets_agent_registry, true})
          :ets.insert(@table_name, {:enable_migration_monitoring, true})
          :ets.insert(@table_name, {:use_logger_error_context, false})
          :ets.insert(@table_name, {:use_genserver_telemetry, false})
          :ets.insert(@table_name, {:use_genserver_span_management, false})
          :ets.insert(@table_name, {:use_ets_sampled_events, false})
          :ets.insert(@table_name, {:enforce_no_process_dict, false})

        2 ->
          # Keep registry and error context - ensure stage 1&2 flags are enabled
          :ets.insert(@table_name, {:use_ets_agent_registry, true})
          :ets.insert(@table_name, {:enable_migration_monitoring, true})
          :ets.insert(@table_name, {:use_logger_error_context, true})
          :ets.insert(@table_name, {:use_genserver_telemetry, false})
          :ets.insert(@table_name, {:use_genserver_span_management, false})
          :ets.insert(@table_name, {:use_ets_sampled_events, false})
          :ets.insert(@table_name, {:enforce_no_process_dict, false})

        3 ->
          # Keep everything except enforcement - ensure stage 1,2,3 flags are enabled
          :ets.insert(@table_name, {:use_ets_agent_registry, true})
          :ets.insert(@table_name, {:enable_migration_monitoring, true})
          :ets.insert(@table_name, {:use_logger_error_context, true})
          :ets.insert(@table_name, {:use_genserver_telemetry, true})
          :ets.insert(@table_name, {:use_genserver_span_management, true})
          :ets.insert(@table_name, {:use_ets_sampled_events, true})
          :ets.insert(@table_name, {:enforce_no_process_dict, false})
      end

      :ets.insert(@table_name, {:migration_stage, target_stage})

      :telemetry.execute(
        [:foundation, :migration, :rollback],
        %{from_stage: current_stage, to_stage: target_stage},
        %{timestamp: System.monotonic_time()}
      )

      {:reply, :ok, state}
    else
      {:reply, {:error, :invalid_rollback}, state}
    end
  end

  @impl true
  def handle_call(:migration_status, _from, state) do
    stage =
      case :ets.lookup(@table_name, :migration_stage) do
        [{:migration_stage, s}] -> s
        [] -> 0
      end

    timestamp =
      case :ets.lookup(@table_name, :migration_timestamp) do
        [{:migration_timestamp, ts}] -> ts
        [] -> nil
      end

    flags =
      Enum.reduce(Map.keys(@otp_cleanup_flags), %{}, fn flag, acc ->
        value =
          case :ets.lookup(@table_name, flag) do
            [{^flag, v}] -> v
            [] -> Map.get(@default_flags, flag, false)
          end

        Map.put(acc, flag, value)
      end)

    status = %{
      stage: stage,
      timestamp: timestamp,
      flags: flags,
      system_time: System.monotonic_time()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:emergency_rollback, reason}, _from, state) do
    Logger.error("EMERGENCY ROLLBACK: #{reason}")

    # Disable all OTP cleanup flags immediately
    Enum.each(Map.keys(@otp_cleanup_flags), fn flag ->
      :ets.insert(@table_name, {flag, false})
    end)

    :ets.insert(@table_name, {:migration_stage, 0})

    :telemetry.execute(
      [:foundation, :migration, :emergency_rollback],
      %{count: 1},
      %{reason: reason, timestamp: System.monotonic_time()}
    )

    {:reply, :ok, state}
  end

  # Private functions

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        # Table doesn't exist, start the GenServer
        case Process.whereis(__MODULE__) do
          nil ->
            {:ok, _pid} = start_link()
            :ok

          _pid ->
            :ok
        end

      _ ->
        :ok
    end
  end

  # Ensure table exists from within GenServer process
  defp ensure_table_exists_in_server do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :public,
          :named_table,
          {:read_concurrency, true}
        ])

      _ ->
        @table_name
    end
  end

  defp load_initial_flags do
    # Load flags from application config
    config_flags = Application.get_env(:foundation, :feature_flags, %{})

    Enum.each(config_flags, fn {flag_name, value} ->
      if Map.has_key?(@default_flags, flag_name) do
        :ets.insert(@table_name, {flag_name, value})
        Logger.info("Loaded feature flag #{flag_name} = #{value} from config")
      else
        Logger.warning("Unknown feature flag in config: #{flag_name}")
      end
    end)
  end
end
