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
    enforce_no_process_dict: false
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
      :ets.insert(@table_name, {flag_name, value})
      Logger.info("Feature flag #{flag_name} set to #{value}")
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
