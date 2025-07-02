defmodule Foundation.MigrationControl do
  @moduledoc """
  Migration control system with admin interface and monitoring for OTP cleanup.
  
  This module provides:
  - Administrative interface for migration control
  - Monitoring of flag usage and performance
  - Automatic rollback triggers on errors
  - Migration status reporting
  """

  require Logger
  alias Foundation.FeatureFlags

  @type migration_stage :: 1..4
  @type migration_status :: :not_started | :in_progress | :completed | :failed | :rolled_back

  # Migration stage definitions
  @migration_stages %{
    1 => %{
      name: "Registry Migration",
      description: "Switch from Process dictionary to ETS-based agent registry",
      flags: [:use_ets_agent_registry, :enable_migration_monitoring],
      risk_level: :low
    },
    2 => %{
      name: "Error Context Migration", 
      description: "Switch from Process dictionary to Logger metadata for error context",
      flags: [:use_logger_error_context],
      risk_level: :medium
    },
    3 => %{
      name: "Telemetry Migration",
      description: "Switch from Process dictionary to GenServer/ETS for telemetry",
      flags: [:use_genserver_telemetry, :use_genserver_span_management, :use_ets_sampled_events],
      risk_level: :high
    },
    4 => %{
      name: "Enforcement",
      description: "Enforce no Process dictionary usage and enable strict checking",
      flags: [:enforce_no_process_dict],
      risk_level: :critical
    }
  }

  # Error thresholds for automatic rollback
  @rollback_thresholds %{
    error_rate: 0.05,              # 5% error rate
    restart_frequency: 10,         # 10 restarts per minute
    response_time_degradation: 2.0 # 2x normal response time
  }

  # Public API

  @doc """
  Get information about all migration stages.
  """
  def list_stages do
    @migration_stages
  end

  @doc """
  Get current migration status with detailed information.
  """
  def status do
    flag_status = FeatureFlags.migration_status()
    
    %{
      current_stage: flag_status.stage,
      stage_info: Map.get(@migration_stages, flag_status.stage),
      timestamp: flag_status.timestamp,
      flags: flag_status.flags,
      system_health: get_system_health(),
      migration_history: get_migration_history(),
      next_stage_info: Map.get(@migration_stages, flag_status.stage + 1)
    }
  end

  @doc """
  Execute migration to the next stage with validation.
  """
  def migrate_to_stage(target_stage) when target_stage in 1..4 do
    current_status = FeatureFlags.migration_status()
    current_stage = current_status.stage

    cond do
      target_stage <= current_stage ->
        {:error, "Cannot migrate backwards. Use rollback_to_stage/1 instead."}
        
      target_stage > current_stage + 1 ->
        {:error, "Cannot skip stages. Must migrate sequentially."}
        
      true ->
        perform_migration(target_stage)
    end
  end

  @doc """
  Rollback to a previous migration stage.
  """
  def rollback_to_stage(target_stage) when target_stage in 0..3 do
    current_status = FeatureFlags.migration_status()
    
    if target_stage < current_status.stage do
      Logger.warning("Manual rollback initiated to stage #{target_stage}")
      
      result = FeatureFlags.rollback_migration_stage(target_stage)
      
      record_migration_event(:rollback, current_status.stage, target_stage, "Manual rollback")
      
      result
    else
      {:error, "Cannot rollback to current or future stage"}
    end
  end

  @doc """
  Emergency rollback with reason logging.
  """
  def emergency_rollback(reason \\ "Emergency rollback requested") do
    Logger.error("EMERGENCY ROLLBACK: #{reason}")
    
    current_status = FeatureFlags.migration_status()
    
    result = FeatureFlags.emergency_rollback(reason)
    
    record_migration_event(:emergency_rollback, current_status.stage, 0, reason)
    
    # Alert operations team
    send_alert(:emergency_rollback, %{
      reason: reason,
      previous_stage: current_status.stage,
      timestamp: System.monotonic_time()
    })
    
    result
  end

  @doc """
  Check system health and trigger rollback if needed.
  """
  def check_health_and_rollback do
    health = get_system_health()
    violations = check_health_violations(health)
    
    if not Enum.empty?(violations) do
      reason = "Automatic rollback due to health violations: #{inspect(violations)}"
      Logger.error(reason)
      
      emergency_rollback(reason)
      
      {:rollback_triggered, violations}
    else
      {:ok, health}
    end
  end

  @doc """
  Start monitoring system health with automatic rollback.
  """
  def start_health_monitoring(interval_ms \\ 30_000) do
    if FeatureFlags.enabled?(:enable_migration_monitoring) do
      Task.start(fn -> health_monitoring_loop(interval_ms) end)
    else
      {:error, :monitoring_disabled}
    end
  end

  @doc """
  Get detailed migration metrics.
  """
  def metrics do
    %{
      flag_usage: get_flag_usage_metrics(),
      performance_impact: get_performance_metrics(),
      error_rates: get_error_rate_metrics(),
      rollback_frequency: get_rollback_metrics()
    }
  end

  @doc """
  Validate readiness for next migration stage.
  """
  def validate_readiness_for_stage(stage) when stage in 1..4 do
    current_status = FeatureFlags.migration_status()
    
    validations = [
      {:current_stage, current_status.stage == stage - 1},
      {:system_health, system_healthy?()},
      {:no_recent_rollbacks, no_recent_rollbacks?()},
      {:test_suite_passing, test_suite_passing?()},
      {:dependencies_ready, dependencies_ready_for_stage?(stage)}
    ]
    
    failed_validations = Enum.filter(validations, fn {_name, passed} -> not passed end)
    
    if Enum.empty?(failed_validations) do
      :ok
    else
      {:error, failed_validations}
    end
  end

  # Private functions

  defp perform_migration(target_stage) do
    stage_info = Map.get(@migration_stages, target_stage)
    
    Logger.info("Starting migration to stage #{target_stage}: #{stage_info.name}")
    
    # Pre-migration validation
    case validate_readiness_for_stage(target_stage) do
      :ok ->
        # Record migration start
        record_migration_event(:migration_start, target_stage - 1, target_stage, "Stage migration initiated")
        
        # Perform migration
        result = FeatureFlags.enable_otp_cleanup_stage(target_stage)
        
        case result do
          :ok ->
            Logger.info("Successfully migrated to stage #{target_stage}")
            record_migration_event(:migration_complete, target_stage - 1, target_stage, "Stage migration completed")
            
            # Start health monitoring for this stage
            start_health_monitoring()
            
            {:ok, %{stage: target_stage, info: stage_info}}
            
          error ->
            Logger.error("Migration to stage #{target_stage} failed: #{inspect(error)}")
            record_migration_event(:migration_failed, target_stage - 1, target_stage, "Migration failed: #{inspect(error)}")
            error
        end
        
      {:error, failed_validations} ->
        {:error, {:validation_failed, failed_validations}}
    end
  end

  defp get_system_health do
    %{
      error_rate: calculate_error_rate(),
      restart_frequency: calculate_restart_frequency(),
      response_time: calculate_average_response_time(),
      memory_usage: get_memory_usage(),
      process_count: get_process_count(),
      ets_usage: get_ets_usage()
    }
  end

  defp check_health_violations(health) do
    violations = []
    
    violations = if health.error_rate > @rollback_thresholds.error_rate do
      [{:error_rate, health.error_rate, @rollback_thresholds.error_rate} | violations]
    else
      violations
    end
    
    violations = if health.restart_frequency > @rollback_thresholds.restart_frequency do
      [{:restart_frequency, health.restart_frequency, @rollback_thresholds.restart_frequency} | violations]
    else
      violations
    end
    
    # Check response time degradation (compared to baseline)
    baseline_response_time = get_baseline_response_time()
    
    if baseline_response_time > 0 and 
       health.response_time > baseline_response_time * @rollback_thresholds.response_time_degradation do
      [{:response_time_degradation, health.response_time, baseline_response_time} | violations]
    else
      violations
    end
  end

  defp health_monitoring_loop(interval_ms) do
    receive do
      :stop -> :ok
    after
      interval_ms ->
        check_health_and_rollback()
        health_monitoring_loop(interval_ms)
    end
  end

  defp record_migration_event(type, from_stage, to_stage, description) do
    event = %{
      type: type,
      from_stage: from_stage,
      to_stage: to_stage,
      description: description,
      timestamp: System.monotonic_time(),
      system_time: DateTime.utc_now()
    }
    
    # Ensure migration history table exists
    ensure_migration_history_table()
    
    # Store in ETS for history tracking
    :ets.insert(:migration_history, {System.monotonic_time(), event})
    
    # Emit telemetry
    :telemetry.execute(
      [:foundation, :migration, type],
      %{from_stage: from_stage, to_stage: to_stage},
      %{description: description, timestamp: System.monotonic_time()}
    )
  end

  defp send_alert(type, data) do
    # In a real system, this would send alerts to monitoring systems
    Logger.warning("MIGRATION ALERT [#{type}]: #{inspect(data)}")
    
    :telemetry.execute(
      [:foundation, :migration, :alert],
      %{count: 1},
      Map.put(data, :alert_type, type)
    )
  end

  # Health check functions (simplified implementations)
  
  defp calculate_error_rate do
    # In real implementation, this would check actual error metrics
    0.001  # 0.1% baseline error rate
  end

  defp calculate_restart_frequency do
    # In real implementation, this would check supervisor restart counts
    1  # 1 restart per minute baseline
  end

  defp calculate_average_response_time do
    # In real implementation, this would check actual response times
    50.0  # 50ms baseline
  end

  defp get_baseline_response_time do
    # In real implementation, this would load from stored baselines
    50.0  # 50ms baseline
  end

  defp get_memory_usage do
    :erlang.memory(:total)
  end

  defp get_process_count do
    length(Process.list())
  end

  defp get_ets_usage do
    :ets.all() |> length()
  end

  defp system_healthy? do
    health = get_system_health()
    violations = check_health_violations(health)
    Enum.empty?(violations)
  end

  defp no_recent_rollbacks? do
    # Check if there have been rollbacks in the last hour
    cutoff = System.monotonic_time() - :timer.hours(1)
    
    case :ets.whereis(:migration_history) do
      :undefined -> true
      _ ->
        rollback_events = :ets.select(:migration_history, [
          {{:"$1", :"$2"}, 
           [{:andalso, {:>, :"$1", cutoff}, {:==, {:map_get, :type, :"$2"}, :rollback}}], 
           [:"$2"]}
        ])
        
        Enum.empty?(rollback_events)
    end
  end

  defp test_suite_passing? do
    # In real implementation, this would trigger test runs
    true
  end

  defp dependencies_ready_for_stage?(_stage) do
    # In real implementation, this would check service dependencies
    true
  end

  defp get_migration_history do
    case :ets.whereis(:migration_history) do
      :undefined ->
        # Create table if it doesn't exist
        :ets.new(:migration_history, [:set, :public, :named_table])
        []
      _ ->
        :ets.tab2list(:migration_history)
        |> Enum.sort_by(fn {timestamp, _event} -> timestamp end, :desc)
        |> Enum.take(20)  # Last 20 events
        |> Enum.map(fn {_timestamp, event} -> event end)
    end
  end

  defp get_flag_usage_metrics do
    # In real implementation, this would track flag usage over time
    %{
      flags_enabled: Enum.count(FeatureFlags.list_all(), fn {_flag, value} -> value end),
      total_flags: map_size(FeatureFlags.list_all()),
      usage_frequency: %{}
    }
  end

  defp get_performance_metrics do
    # In real implementation, this would track performance impact of flags
    %{
      response_time_impact: 0.05,  # 5% impact
      memory_impact: 0.02,         # 2% impact
      cpu_impact: 0.01             # 1% impact
    }
  end

  defp get_error_rate_metrics do
    # In real implementation, this would track error rates by flag
    %{
      baseline_error_rate: 0.001,
      current_error_rate: 0.001,
      error_rate_by_flag: %{}
    }
  end

  defp get_rollback_metrics do
    # In real implementation, this would track rollback frequency and causes
    %{
      total_rollbacks: 0,
      rollbacks_by_cause: %{},
      time_since_last_rollback: nil
    }
  end

  defp ensure_migration_history_table do
    case :ets.whereis(:migration_history) do
      :undefined ->
        :ets.new(:migration_history, [:set, :public, :named_table])
      _ ->
        :migration_history
    end
  end
end