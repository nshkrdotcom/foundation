defmodule Foundation.Validation.ConfigValidator do
  @moduledoc """
  Pure validation functions for configuration structures.

  Contains only validation logic - no side effects, no GenServer calls.
  All functions are pure and easily testable.
  """

  alias Foundation.Types.{Config, Error}

  @doc """
  Validate a complete configuration structure.
  """
  @spec validate(Config.t()) :: :ok | {:error, Error.t()}
  def validate(%Config{} = config) do
    with :ok <- validate_ai_config(config.ai),
         :ok <- validate_capture_config(config.capture),
         :ok <- validate_storage_config(config.storage),
         :ok <- validate_interface_config(config.interface),
         :ok <- validate_dev_config(config.dev),
         :ok <- validate_infrastructure_config(config.infrastructure) do
      :ok
    end
  end

  @doc """
  Validate AI configuration section.
  """
  @spec validate_ai_config(map()) :: :ok | {:error, Error.t()}
  def validate_ai_config(%{provider: provider} = config) do
    with :ok <- validate_provider(provider),
         :ok <- validate_ai_analysis(config.analysis),
         :ok <- validate_ai_planning(config.planning) do
      :ok
    end
  end

  @doc """
  Validate capture configuration section.
  """
  @spec validate_capture_config(map()) :: :ok | {:error, Error.t()}
  def validate_capture_config(%{ring_buffer: rb, processing: proc, vm_tracing: vt}) do
    with :ok <- validate_ring_buffer(rb),
         :ok <- validate_processing(proc),
         :ok <- validate_vm_tracing(vt) do
      :ok
    end
  end

  @doc """
  Validate storage configuration section.
  """
  @spec validate_storage_config(map()) :: :ok | {:error, Error.t()}
  def validate_storage_config(%{hot: hot, warm: warm, cold: cold}) do
    with :ok <- validate_hot_storage(hot),
         :ok <- validate_warm_storage(warm),
         :ok <- validate_cold_storage(cold) do
      :ok
    end
  end

  @doc """
  Validate interface configuration section.
  """
  @spec validate_interface_config(map()) :: :ok | {:error, Error.t()}
  def validate_interface_config(%{
        query_timeout: timeout,
        max_results: max,
        enable_streaming: stream
      })
      when is_integer(timeout) and timeout > 0 and
             is_integer(max) and max > 0 and
             is_boolean(stream) do
    :ok
  end

  def validate_interface_config(_) do
    create_validation_error("Invalid interface configuration")
  end

  @doc """
  Validate development configuration section.
  """
  @spec validate_dev_config(map()) :: :ok | {:error, Error.t()}
  def validate_dev_config(%{
        debug_mode: debug,
        verbose_logging: verbose,
        performance_monitoring: perf
      })
      when is_boolean(debug) and is_boolean(verbose) and is_boolean(perf) do
    :ok
  end

  @spec validate_dev_config(map()) :: {:error, Error.t()}
  def validate_dev_config(_) do
    create_validation_error("Invalid development configuration")
  end

  @doc """
  Validate infrastructure configuration section.
  """
  @spec validate_infrastructure_config(map()) :: :ok | {:error, Error.t()}
  def validate_infrastructure_config(%{
        rate_limiting: rate_limiting,
        circuit_breaker: circuit_breaker,
        connection_pool: connection_pool
      }) do
    with :ok <- validate_rate_limiting_config(rate_limiting),
         :ok <- validate_circuit_breaker_config(circuit_breaker),
         :ok <- validate_connection_pool_config(connection_pool) do
      :ok
    end
  end

  def validate_infrastructure_config(_) do
    create_validation_error("Invalid infrastructure configuration")
  end

  ## Private Validation Functions

  defp validate_provider(provider) do
    valid_providers = [:mock, :openai, :anthropic, :gemini]

    if provider in valid_providers do
      :ok
    else
      create_error(
        :invalid_config_value,
        "Invalid AI provider",
        %{provider: provider, valid_providers: valid_providers}
      )
    end
  end

  defp validate_ai_analysis(%{max_file_size: size, timeout: timeout, cache_ttl: ttl})
       when is_integer(size) and size > 0 and
              is_integer(timeout) and timeout > 0 and
              is_integer(ttl) and ttl > 0 do
    :ok
  end

  defp validate_ai_analysis(_) do
    create_validation_error("Invalid AI analysis configuration")
  end

  defp validate_ai_planning(%{
         performance_target: target,
         sampling_rate: rate,
         default_strategy: strategy
       }) do
    valid_strategies = [:fast, :balanced, :thorough]

    cond do
      not is_number(target) or target < 0 ->
        create_error(:constraint_violation, "Performance target must be a non-negative number")

      not is_number(rate) or rate < 0 or rate > 1 ->
        create_error(:range_error, "Sampling rate must be between 0 and 1")

      strategy not in valid_strategies ->
        create_error(:invalid_config_value, "Invalid planning strategy")

      true ->
        :ok
    end
  end

  defp validate_ai_planning(_) do
    create_validation_error("Invalid AI planning configuration")
  end

  defp validate_ring_buffer(%{size: size, max_events: max, overflow_strategy: strategy})
       when is_integer(size) and size > 0 and
              is_integer(max) and max > 0 do
    valid_strategies = [:drop_oldest, :drop_newest, :block]

    if strategy in valid_strategies do
      :ok
    else
      create_error(:invalid_config_value, "Invalid overflow strategy")
    end
  end

  defp validate_ring_buffer(_) do
    create_validation_error("Invalid ring buffer configuration")
  end

  defp validate_processing(%{batch_size: batch, flush_interval: flush, max_queue_size: queue})
       when is_integer(batch) and batch > 0 and
              is_integer(flush) and flush > 0 and
              is_integer(queue) and queue > 0 do
    :ok
  end

  defp validate_processing(_) do
    create_validation_error("Invalid processing configuration")
  end

  defp validate_vm_tracing(%{
         enable_spawn_trace: spawn,
         enable_exit_trace: exit,
         enable_message_trace: msg,
         trace_children: children
       })
       when is_boolean(spawn) and is_boolean(exit) and
              is_boolean(msg) and is_boolean(children) do
    :ok
  end

  defp validate_vm_tracing(_) do
    create_validation_error("Invalid VM tracing configuration")
  end

  defp validate_hot_storage(%{max_events: max, max_age_seconds: age, prune_interval: interval})
       when is_integer(max) and max > 0 and
              is_integer(age) and age > 0 and
              is_integer(interval) and interval > 0 do
    :ok
  end

  defp validate_hot_storage(_) do
    create_validation_error("Invalid hot storage configuration")
  end

  defp validate_warm_storage(%{enable: false}), do: :ok

  defp validate_warm_storage(%{enable: true, path: path, max_size_mb: size, compression: comp})
       when is_binary(path) and is_integer(size) and size > 0 do
    valid_compression = [:none, :gzip, :zstd]

    if comp in valid_compression do
      :ok
    else
      create_error(:invalid_config_value, "Invalid compression type")
    end
  end

  defp validate_warm_storage(_) do
    create_validation_error("Invalid warm storage configuration")
  end

  defp validate_cold_storage(%{enable: false}), do: :ok

  defp validate_cold_storage(_) do
    create_validation_error("Invalid cold storage configuration")
  end

  ## Error Creation Helpers

  @spec create_validation_error(String.t()) :: {:error, Error.t()}
  defp create_validation_error(message) do
    create_error(:validation_failed, message)
  end

  # Infrastructure validation helpers
  defp validate_rate_limiting_config(%{
         default_rules: rules,
         enabled: enabled,
         cleanup_interval: interval
       })
       when is_map(rules) and is_boolean(enabled) and is_integer(interval) and interval > 0 do
    validate_rate_limiting_rules(rules)
  end

  defp validate_rate_limiting_config(_) do
    create_validation_error("Invalid rate limiting configuration")
  end

  defp validate_rate_limiting_rules(rules) when is_map(rules) do
    Enum.reduce_while(rules, :ok, fn {rule_name, rule_config}, _acc ->
      case validate_rate_limiting_rule(rule_name, rule_config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_rate_limiting_rule(rule_name, %{scale: scale, limit: limit})
       when is_atom(rule_name) and is_integer(scale) and scale > 0 and
              is_integer(limit) and limit > 0 do
    :ok
  end

  defp validate_rate_limiting_rule(rule_name, _) do
    create_validation_error("Invalid rate limiting rule: #{inspect(rule_name)}")
  end

  defp validate_circuit_breaker_config(%{
         default_config: config,
         enabled: enabled
       })
       when is_map(config) and is_boolean(enabled) do
    validate_circuit_breaker_default_config(config)
  end

  defp validate_circuit_breaker_config(_) do
    create_validation_error("Invalid circuit breaker configuration")
  end

  defp validate_circuit_breaker_default_config(%{
         failure_threshold: threshold,
         recovery_time: recovery,
         call_timeout: timeout
       })
       when is_integer(threshold) and threshold > 0 and
              is_integer(recovery) and recovery > 0 and
              is_integer(timeout) and timeout > 0 do
    :ok
  end

  defp validate_circuit_breaker_default_config(_) do
    create_validation_error("Invalid circuit breaker default configuration")
  end

  defp validate_connection_pool_config(%{
         default_config: config,
         enabled: enabled
       })
       when is_map(config) and is_boolean(enabled) do
    validate_connection_pool_default_config(config)
  end

  defp validate_connection_pool_config(_) do
    create_validation_error("Invalid connection pool configuration")
  end

  defp validate_connection_pool_default_config(%{
         size: size,
         max_overflow: overflow,
         strategy: strategy
       })
       when is_integer(size) and size > 0 and
              is_integer(overflow) and overflow >= 0 and
              strategy in [:lifo, :fifo] do
    :ok
  end

  defp validate_connection_pool_default_config(_) do
    create_validation_error("Invalid connection pool default configuration")
  end

  @spec create_error(atom(), String.t(), map()) :: {:error, Error.t()}
  defp create_error(error_type, message, context \\ %{}) do
    error =
      Error.new(
        code: error_code_for_type(error_type),
        error_type: error_type,
        message: message,
        severity: severity_for_type(error_type),
        context: context,
        category: :config,
        subcategory: :validation
      )

    {:error, error}
  end

  @spec error_code_for_type(
          :validation_failed
          | :invalid_config_value
          | :constraint_violation
          | :range_error
        ) :: 1001 | 1002 | 1003 | 1004
  defp error_code_for_type(:validation_failed), do: 1001
  defp error_code_for_type(:invalid_config_value), do: 1002
  defp error_code_for_type(:constraint_violation), do: 1003
  defp error_code_for_type(:range_error), do: 1004

  @spec severity_for_type(
          :validation_failed
          | :invalid_config_value
          | :constraint_violation
          | :range_error
        ) :: Error.error_severity()
  defp severity_for_type(:constraint_violation), do: :high
  defp severity_for_type(:range_error), do: :high
  defp severity_for_type(_), do: :medium
end
