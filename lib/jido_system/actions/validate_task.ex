defmodule JidoSystem.Actions.ValidateTask do
  @moduledoc """
  Comprehensive task validation action with circuit breaker protection.

  This action performs thorough validation of task parameters, input data,
  and business rules before task execution. It includes built-in circuit
  breaker protection for external validation services.

  ## Features
  - Multi-level validation (syntax, semantics, business rules)
  - Schema validation with detailed error reporting
  - Circuit breaker protection for external validators
  - Configurable validation rules and policies
  - Performance monitoring and telemetry
  - Validation result caching

  ## Validation Levels
  1. **Syntax Validation** - Basic structure and type checking
  2. **Semantic Validation** - Logical consistency and constraints
  3. **Business Rules** - Domain-specific validation logic
  4. **External Validation** - Third-party service validation

  ## Usage

      params = %{
        task: %{
          id: "task_123",
          type: :data_processing,
          input: %{file: "data.csv"},
          config: %{format: "csv", delimiter: ","}
        },
        validation_rules: [:syntax, :semantics, :business_rules],
        strict: true,
        cache_results: true
      }

      {:ok, validated_task} = ValidateTask.run(params, context, opts)
  """

  use Jido.Action,
    name: "validate_task",
    description: "Comprehensive task validation with circuit breaker protection",
    schema: [
      task: [type: :map, required: true, doc: "Task to validate"],
      validation_rules: [
        type: {:list, :atom},
        default: [:syntax, :semantics],
        doc: "List of validation rules to apply"
      ],
      strict: [type: :boolean, default: false, doc: "Enable strict validation mode"],
      cache_results: [type: :boolean, default: true, doc: "Cache validation results"],
      timeout: [type: :integer, default: 10_000, doc: "Validation timeout in milliseconds"],
      external_validators: [type: :list, default: [], doc: "External validation services"],
      business_rules: [type: :map, default: %{}, doc: "Custom business rule configuration"]
    ]

  require Logger
  alias Foundation.{CircuitBreaker, Cache}

  @impl true
  def run(params, context) do
    task = params.task
    task_id = Map.get(task, :id, "unknown")
    start_time = System.monotonic_time(:microsecond)

    Logger.info("Starting task validation",
      task_id: task_id,
      validation_rules: params.validation_rules
    )

    # Emit start telemetry
    :telemetry.execute([:jido_system, :validation, :started], %{count: 1}, %{
      task_id: task_id,
      validation_rules: params.validation_rules,
      strict: params.strict,
      agent_id: Map.get(context, :agent_id)
    })

    try do
      # Check cache if enabled
      cache_key = generate_cache_key(task, params.validation_rules)

      cached_result =
        if params.cache_results do
          Cache.get(cache_key)
        else
          nil
        end

      case cached_result do
        nil ->
          # Perform validation
          result = perform_validation(task, params, context)

          # Cache result if successful and caching enabled
          if params.cache_results and match?({:ok, _}, result) do
            # 5 minutes
            Cache.put(cache_key, result, ttl: 300_000)
          end

          emit_validation_telemetry(result, task_id, start_time, context, false)
          result

        cached ->
          Logger.debug("Using cached validation result", task_id: task_id)
          emit_validation_telemetry(cached, task_id, start_time, context, true)
          cached
      end
    rescue
      e ->
        duration = System.monotonic_time(:microsecond) - start_time

        Logger.error("Validation crashed",
          task_id: task_id,
          error: inspect(e),
          stacktrace: __STACKTRACE__
        )

        # Emit error telemetry
        :telemetry.execute(
          [:jido_system, :validation, :error],
          %{
            duration: duration,
            count: 1
          },
          %{
            task_id: task_id,
            error: inspect(e),
            agent_id: Map.get(context, :agent_id)
          }
        )

        {:error, {:validation_crashed, e}}
    end
  end

  # Private helper functions

  defp perform_validation(task, params, context) do
    validation_results = %{
      task_id: Map.get(task, :id),
      validation_rules: params.validation_rules,
      results: %{},
      errors: [],
      warnings: [],
      strict: params.strict,
      validated_at: DateTime.utc_now()
    }

    # Apply each validation rule in sequence
    final_result =
      Enum.reduce_while(params.validation_rules, {:ok, validation_results}, fn rule, {:ok, acc} ->
        case apply_validation_rule(rule, task, params, context) do
          {:ok, rule_result} ->
            updated_acc = %{acc | results: Map.put(acc.results, rule, rule_result)}
            {:cont, {:ok, updated_acc}}

          {:warning, rule_result, warnings} ->
            updated_acc = %{
              acc
              | results: Map.put(acc.results, rule, rule_result),
                warnings: acc.warnings ++ warnings
            }

            # Continue on warnings unless strict mode
            if params.strict do
              {:halt, {:error, {:strict_validation_failed, warnings}}}
            else
              {:cont, {:ok, updated_acc}}
            end

          {:error, reason} ->
            error_info = %{rule: rule, reason: reason}
            updated_acc = %{acc | errors: [error_info | acc.errors]}
            {:halt, {:error, updated_acc}}
        end
      end)

    case final_result do
      {:ok, results} ->
        if Enum.empty?(results.errors) do
          validated_task = enhance_task_with_validation(task, results)
          {:ok, validated_task}
        else
          {:error, results}
        end

      {:error, results} ->
        {:error, results}
    end
  end

  defp apply_validation_rule(:syntax, task, _params, _context) do
    Logger.debug("Applying syntax validation", task_id: Map.get(task, :id))

    errors = []

    # Required fields validation
    errors =
      if not Map.has_key?(task, :id) or not is_binary(task.id) do
        ["Missing or invalid task ID" | errors]
      else
        errors
      end

    errors =
      if not Map.has_key?(task, :type) or not is_atom(task.type) do
        ["Missing or invalid task type" | errors]
      else
        errors
      end

    # Input validation
    errors =
      case Map.get(task, :input) do
        input when is_map(input) -> errors
        nil -> ["Missing task input" | errors]
        _ -> ["Invalid task input format" | errors]
      end

    # Configuration validation
    errors =
      case Map.get(task, :config) do
        config when is_map(config) -> errors
        # Config is optional
        nil -> errors
        _ -> ["Invalid task configuration format" | errors]
      end

    if Enum.empty?(errors) do
      {:ok, %{status: :valid, checked_fields: [:id, :type, :input, :config]}}
    else
      {:error, {:syntax_errors, errors}}
    end
  end

  defp apply_validation_rule(:semantics, task, _params, _context) do
    Logger.debug("Applying semantic validation", task_id: Map.get(task, :id))

    warnings = []
    errors = []

    # Check task type compatibility
    task_type = Map.get(task, :type)
    input_data = Map.get(task, :input, %{})

    {errors, warnings} =
      case task_type do
        :data_processing ->
          validate_data_processing_task(input_data, errors, warnings)

        :validation ->
          validate_validation_task(input_data, errors, warnings)

        :transformation ->
          validate_transformation_task(input_data, errors, warnings)

        :analysis ->
          validate_analysis_task(input_data, errors, warnings)

        :notification ->
          validate_notification_task(input_data, errors, warnings)

        unknown_type ->
          {["Unsupported task type: #{unknown_type}" | errors], warnings}
      end

    cond do
      not Enum.empty?(errors) ->
        {:error, {:semantic_errors, errors}}

      not Enum.empty?(warnings) ->
        {:warning, %{status: :valid_with_warnings, warnings: warnings}, warnings}

      true ->
        {:ok, %{status: :valid, task_type: task_type}}
    end
  end

  defp apply_validation_rule(:business_rules, task, params, context) do
    Logger.debug("Applying business rules validation", task_id: Map.get(task, :id))

    business_rules = params.business_rules
    agent_id = Map.get(context, :agent_id)

    # Apply configured business rules
    rule_results =
      Enum.map(business_rules, fn {rule_name, rule_config} ->
        apply_business_rule(rule_name, rule_config, task, context)
      end)

    failed_rules =
      Enum.filter(rule_results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_rules) do
      {:ok,
       %{
         status: :valid,
         business_rules_applied: Map.keys(business_rules),
         agent_id: agent_id
       }}
    else
      {:error, {:business_rule_violations, failed_rules}}
    end
  end

  defp apply_validation_rule(:external, task, params, _context) do
    Logger.debug("Applying external validation", task_id: Map.get(task, :id))

    external_validators = params.external_validators
    timeout = params.timeout

    if Enum.empty?(external_validators) do
      {:ok, %{status: :skipped, reason: "No external validators configured"}}
    else
      # Use circuit breaker for external validation
      circuit_breaker_name = "external_validator"

      CircuitBreaker.call(
        circuit_breaker_name,
        fn ->
          validate_with_external_services(task, external_validators, timeout)
        end,
        failure_threshold: 3,
        recovery_timeout: 30_000,
        timeout: timeout
      )
    end
  end

  defp apply_validation_rule(unknown_rule, task, _params, _context) do
    Logger.warning("Unknown validation rule",
      rule: unknown_rule,
      task_id: Map.get(task, :id)
    )

    {:error, {:unknown_validation_rule, unknown_rule}}
  end

  defp validate_data_processing_task(input_data, errors, warnings) do
    # Check for required data processing fields
    errors =
      if not Map.has_key?(input_data, :source) do
        ["Data processing requires 'source' field" | errors]
      else
        errors
      end

    # Check for optional but recommended fields
    warnings =
      if not Map.has_key?(input_data, :format) do
        ["Consider specifying data format for better processing" | warnings]
      else
        warnings
      end

    warnings =
      if not Map.has_key?(input_data, :validation_rules) do
        ["Consider adding validation rules for data quality" | warnings]
      else
        warnings
      end

    {errors, warnings}
  end

  defp validate_validation_task(input_data, errors, warnings) do
    # Check for validation-specific requirements
    errors =
      if not Map.has_key?(input_data, :data) do
        ["Validation task requires 'data' field" | errors]
      else
        errors
      end

    warnings =
      if not Map.has_key?(input_data, :schema) do
        ["Consider providing validation schema" | warnings]
      else
        warnings
      end

    {errors, warnings}
  end

  defp validate_transformation_task(input_data, errors, warnings) do
    # Check transformation requirements
    errors =
      if not Map.has_key?(input_data, :transformations) do
        ["Transformation task requires 'transformations' field" | errors]
      else
        errors
      end

    errors =
      if not Map.has_key?(input_data, :target_format) do
        ["Transformation task requires 'target_format' field" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp validate_analysis_task(input_data, errors, warnings) do
    # Check analysis requirements
    errors =
      if not Map.has_key?(input_data, :analysis_type) do
        ["Analysis task requires 'analysis_type' field" | errors]
      else
        errors
      end

    warnings =
      if not Map.has_key?(input_data, :parameters) do
        ["Consider providing analysis parameters" | warnings]
      else
        warnings
      end

    {errors, warnings}
  end

  defp validate_notification_task(input_data, errors, warnings) do
    # Check notification requirements
    errors =
      if not Map.has_key?(input_data, :recipients) do
        ["Notification task requires 'recipients' field" | errors]
      else
        errors
      end

    errors =
      if not Map.has_key?(input_data, :message) do
        ["Notification task requires 'message' field" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp apply_business_rule(:max_input_size, config, task, _context) do
    # 1MB default
    max_size = Map.get(config, :max_size, 1_000_000)
    input_data = Map.get(task, :input, %{})

    # Estimate input size (simplified)
    estimated_size = :erlang.external_size(input_data)

    if estimated_size <= max_size do
      {:ok, %{rule: :max_input_size, size: estimated_size, limit: max_size}}
    else
      {:error,
       %{
         rule: :max_input_size,
         size: estimated_size,
         limit: max_size,
         message: "Input size exceeds maximum allowed"
       }}
    end
  end

  defp apply_business_rule(:allowed_task_types, config, task, _context) do
    allowed_types = Map.get(config, :types, [])
    task_type = Map.get(task, :type)

    if Enum.empty?(allowed_types) or task_type in allowed_types do
      {:ok, %{rule: :allowed_task_types, type: task_type}}
    else
      {:error,
       %{
         rule: :allowed_task_types,
         type: task_type,
         allowed: allowed_types,
         message: "Task type not in allowed list"
       }}
    end
  end

  defp apply_business_rule(:rate_limit, config, _task, context) do
    agent_id = Map.get(context, :agent_id, "unknown")
    # seconds
    window = Map.get(config, :window, 60)
    # tasks per window
    limit = Map.get(config, :limit, 100)

    # Check rate limit (simplified implementation)
    cache_key = "rate_limit:#{agent_id}:#{div(System.system_time(:second), window)}"
    current_count = Cache.get(cache_key, 0)

    if current_count < limit do
      Cache.put(cache_key, current_count + 1, ttl: window * 1000)
      {:ok, %{rule: :rate_limit, count: current_count + 1, limit: limit}}
    else
      {:error,
       %{rule: :rate_limit, count: current_count, limit: limit, message: "Rate limit exceeded"}}
    end
  end

  defp apply_business_rule(rule_name, _config, _task, _context) do
    Logger.warning("Unknown business rule", rule: rule_name)
    {:error, %{rule: rule_name, message: "Unknown business rule"}}
  end

  defp validate_with_external_services(task, validators, timeout) do
    # Simulate external validation calls
    results =
      Enum.map(validators, fn validator ->
        case validator do
          %{type: :schema_validator, endpoint: endpoint} ->
            validate_with_schema_service(task, endpoint, timeout)

          %{type: :data_quality, endpoint: endpoint} ->
            validate_with_data_quality_service(task, endpoint, timeout)

          %{type: :compliance, endpoint: endpoint} ->
            validate_with_compliance_service(task, endpoint, timeout)

          _ ->
            {:error, {:invalid_validator_config, validator}}
        end
      end)

    failed_validations =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed_validations) do
      {:ok,
       %{
         status: :valid,
         external_validators: length(validators),
         validation_results: results
       }}
    else
      {:error, {:external_validation_failed, failed_validations}}
    end
  end

  defp validate_with_schema_service(task, endpoint, _timeout) do
    # Simulate HTTP call to schema validation service
    Logger.debug("Validating with schema service", endpoint: endpoint)

    # Mock validation result
    if Map.has_key?(task, :id) and Map.has_key?(task, :type) do
      {:ok, %{service: :schema_validator, result: :valid, endpoint: endpoint}}
    else
      {:error,
       %{
         service: :schema_validator,
         result: :invalid,
         reason: "Missing required fields",
         endpoint: endpoint
       }}
    end
  end

  defp validate_with_data_quality_service(task, endpoint, _timeout) do
    # Simulate data quality check
    Logger.debug("Validating with data quality service", endpoint: endpoint)

    input_data = Map.get(task, :input, %{})
    quality_score = calculate_mock_quality_score(input_data)

    if quality_score >= 0.7 do
      {:ok, %{service: :data_quality, result: :valid, score: quality_score, endpoint: endpoint}}
    else
      {:error,
       %{
         service: :data_quality,
         result: :invalid,
         score: quality_score,
         reason: "Data quality below threshold",
         endpoint: endpoint
       }}
    end
  end

  defp validate_with_compliance_service(task, endpoint, _timeout) do
    # Simulate compliance check
    Logger.debug("Validating with compliance service", endpoint: endpoint)

    # Mock compliance validation
    task_type = Map.get(task, :type)
    compliant_types = [:data_processing, :validation, :analysis]

    if task_type in compliant_types do
      {:ok, %{service: :compliance, result: :compliant, endpoint: endpoint}}
    else
      {:error,
       %{
         service: :compliance,
         result: :non_compliant,
         reason: "Task type not in compliance list",
         endpoint: endpoint
       }}
    end
  end

  defp calculate_mock_quality_score(input_data) do
    # Simple quality scoring based on data completeness
    total_fields = map_size(input_data)

    non_empty_fields =
      Enum.count(input_data, fn {_, v} ->
        not is_nil(v) and v != "" and v != []
      end)

    if total_fields > 0 do
      non_empty_fields / total_fields
    else
      0.0
    end
  end

  defp enhance_task_with_validation(task, validation_results) do
    validation_metadata = %{
      validated: true,
      validation_timestamp: validation_results.validated_at,
      validation_rules: validation_results.validation_rules,
      validation_id: generate_validation_id(),
      warnings: validation_results.warnings
    }

    # Add validation metadata to task
    Map.update(task, :metadata, validation_metadata, fn existing ->
      Map.merge(existing, validation_metadata)
    end)
  end

  defp generate_cache_key(task, validation_rules) do
    task_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary(task))
      |> Base.encode16(case: :lower)

    rules_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary(validation_rules))
      |> Base.encode16(case: :lower)

    "task_validation:#{task_hash}:#{rules_hash}"
  end

  defp generate_validation_id() do
    "val_#{System.unique_integer()}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp emit_validation_telemetry(result, task_id, start_time, context, from_cache) do
    duration = System.monotonic_time(:microsecond) - start_time

    case result do
      {:ok, _validated_task} ->
        :telemetry.execute(
          [:jido_system, :validation, :completed],
          %{
            duration: duration,
            count: 1
          },
          %{
            task_id: task_id,
            result: :success,
            from_cache: from_cache,
            agent_id: Map.get(context, :agent_id)
          }
        )

      {:error, error_details} ->
        :telemetry.execute(
          [:jido_system, :validation, :failed],
          %{
            duration: duration,
            count: 1
          },
          %{
            task_id: task_id,
            error_type: determine_error_type(error_details),
            from_cache: from_cache,
            agent_id: Map.get(context, :agent_id)
          }
        )
    end
  end

  defp determine_error_type(%{errors: errors}) when is_list(errors) and length(errors) > 0 do
    :validation_errors
  end

  defp determine_error_type({:syntax_errors, _}), do: :syntax_error
  defp determine_error_type({:semantic_errors, _}), do: :semantic_error
  defp determine_error_type({:business_rule_violations, _}), do: :business_rule_error
  defp determine_error_type({:external_validation_failed, _}), do: :external_validation_error
  defp determine_error_type(_), do: :unknown_error
end
