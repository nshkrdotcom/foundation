defmodule JidoSystem.Actions.ProcessTask do
  @moduledoc """
  Production-ready task processing action with circuit breaker protection.

  This action handles the core task processing logic with built-in reliability
  features including circuit breakers, retry mechanisms, and comprehensive
  error handling.

  ## Features
  - Circuit breaker protection for external dependencies
  - Configurable retry policies with exponential backoff
  - Comprehensive input validation
  - Detailed telemetry and logging
  - Graceful error handling and recovery
  - Task progress tracking

  ## Usage

      params = %{
        task_id: "task_123",
        task_type: :data_processing,
        input_data: %{file: "data.csv"},
        options: %{
          timeout: 30_000,
          retry_attempts: 3,
          circuit_breaker: true
        }
      }

      {:ok, result} = ProcessTask.run(params, context, opts)
  """

  use Jido.Action,
    name: "process_task",
    description: "Process tasks with circuit breaker protection and retry logic",
    schema: [
      task_id: [type: :string, required: true, doc: "Unique task identifier"],
      task_type: [type: :atom, required: true, doc: "Type of task to process"],
      input_data: [type: :map, default: %{}, doc: "Task input data"],
      options: [type: :map, default: %{}, doc: "Processing options and configuration"],
      priority: [type: :atom, default: :normal, doc: "Task priority level"],
      timeout: [type: :integer, default: 30_000, doc: "Task timeout in milliseconds"],
      retry_attempts: [type: :integer, default: 3, doc: "Number of retry attempts"],
      circuit_breaker: [type: :boolean, default: true, doc: "Enable circuit breaker protection"]
    ]

  require Logger

  @impl true
  def run(params, context) do
    task_id = params.task_id
    task_type = params.task_type
    start_time = System.monotonic_time(:microsecond)

    Logger.info("Starting task processing", task_id: task_id, task_type: task_type)

    # Emit start telemetry
    :telemetry.execute([:jido_system, :task, :started], %{count: 1}, %{
      task_id: task_id,
      task_type: task_type,
      agent_id: Map.get(context, :agent_id)
    })

    try do
      # Validate task parameters
      case validate_task_params(params) do
        :ok ->
          # Process with circuit breaker protection if enabled
          result =
            if params.circuit_breaker do
              process_with_circuit_breaker(params, context)
            else
              process_task_direct(params, context)
            end

          case result do
            {:ok, task_result} ->
              duration = System.monotonic_time(:microsecond) - start_time

              Logger.info("Task completed successfully",
                task_id: task_id,
                duration_ms: div(duration, 1000)
              )

              # Emit success telemetry
              :telemetry.execute(
                [:jido_system, :task, :completed],
                %{
                  duration: duration,
                  count: 1
                },
                %{
                  task_id: task_id,
                  task_type: task_type,
                  result: :success,
                  agent_id: Map.get(context, :agent_id)
                }
              )

              {:ok,
               %{
                 task_id: task_id,
                 result: task_result,
                 duration: duration,
                 status: :completed,
                 completed_at: DateTime.utc_now()
               }}

            {:error, reason} ->
              duration = System.monotonic_time(:microsecond) - start_time

              Logger.error("Task processing failed",
                task_id: task_id,
                reason: inspect(reason),
                duration_ms: div(duration, 1000)
              )

              # Emit failure telemetry
              :telemetry.execute(
                [:jido_system, :task, :failed],
                %{
                  duration: duration,
                  count: 1
                },
                %{
                  task_id: task_id,
                  task_type: task_type,
                  reason: reason,
                  agent_id: Map.get(context, :agent_id)
                }
              )

              {:error,
               %{
                 task_id: task_id,
                 error: reason,
                 duration: duration,
                 status: :failed,
                 failed_at: DateTime.utc_now()
               }}
          end

        {:error, validation_error} ->
          Logger.warning("Task validation failed",
            task_id: task_id,
            error: inspect(validation_error)
          )

          {:error, {:validation_failed, validation_error}}
      end
    rescue
      e ->
        duration = System.monotonic_time(:microsecond) - start_time

        Logger.error("Task processing crashed",
          task_id: task_id,
          error: inspect(e),
          stacktrace: __STACKTRACE__
        )

        # Emit error telemetry
        :telemetry.execute(
          [:jido_system, :task, :error],
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

        {:error, {:processing_crashed, e}}
    end
  end

  # Private helper functions

  defp validate_task_params(params) do
    cond do
      not is_binary(params.task_id) or String.length(params.task_id) == 0 ->
        {:error, :invalid_task_id}

      not is_atom(params.task_type) ->
        {:error, :invalid_task_type}

      not is_map(params.input_data) ->
        {:error, :invalid_input_data}

      params.timeout < 1000 ->
        {:error, :timeout_too_short}

      params.retry_attempts < 0 ->
        {:error, :invalid_retry_attempts}

      true ->
        :ok
    end
  end

  defp process_with_circuit_breaker(params, context) do
    # Use Foundation.Services.RetryService with circuit breaker integration
    circuit_breaker_id = :"task_processor_#{params.task_type}"
    retry_policy = get_retry_policy_for_task_type(params.task_type)

    telemetry_metadata = %{
      task_id: params.task_id,
      task_type: params.task_type,
      agent_id: Map.get(context, :agent_id),
      circuit_breaker_id: circuit_breaker_id
    }

    case Foundation.Services.RetryService.retry_with_circuit_breaker(
           circuit_breaker_id,
           fn -> execute_task_logic(params, context) end,
           policy: retry_policy,
           max_retries: params.retry_attempts,
           telemetry_metadata: telemetry_metadata
         ) do
      {:ok, result} ->
        {:ok, result}

      {:error, :circuit_open} ->
        Logger.warning("Circuit breaker open, rejecting task",
          task_id: params.task_id,
          circuit_breaker_id: circuit_breaker_id
        )

        {:error, :circuit_breaker_open}

      {:error, reason} ->
        Logger.error("Task failed with circuit breaker protection",
          task_id: params.task_id,
          reason: inspect(reason),
          circuit_breaker_id: circuit_breaker_id
        )

        {:error, reason}
    end
  end

  defp process_task_direct(params, context) do
    process_with_retry(params, context, params.retry_attempts)
  end

  defp process_with_retry(params, context, attempts_remaining) when attempts_remaining > 0 do
    # Use Foundation.Services.RetryService for production-grade retry logic
    retry_policy = get_retry_policy_for_task_type(params.task_type)

    telemetry_metadata = %{
      task_id: params.task_id,
      task_type: params.task_type,
      agent_id: Map.get(context, :agent_id),
      retry_attempts: attempts_remaining
    }

    case Foundation.Services.RetryService.retry_operation(
           fn -> execute_task_logic(params, context) end,
           policy: retry_policy,
           max_retries: attempts_remaining,
           telemetry_metadata: telemetry_metadata
         ) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Task failed after all retries with RetryService",
          task_id: params.task_id,
          final_reason: inspect(reason),
          retry_policy: retry_policy
        )

        {:error, {:retries_exhausted, reason}}
    end
  end

  defp process_with_retry(_params, _context, 0) do
    {:error, :no_attempts_remaining}
  end

  # Enhanced retry policy selection based on task type
  defp get_retry_policy_for_task_type(task_type) do
    case task_type do
      # Network-related tasks benefit from exponential backoff
      type when type in [:api_call, :external_service, :http_request, :network_task] ->
        :exponential_backoff

      # Quick tasks can retry immediately
      type when type in [:validation, :simple_computation, :quick_task] ->
        :immediate

      # Batch/processing tasks benefit from linear backoff
      type when type in [:data_processing, :file_processing, :batch_task] ->
        :linear_backoff

      # Default to exponential backoff for unknown task types
      _ ->
        :exponential_backoff
    end
  end

  defp execute_task_logic(params, context) do
    # Emit progress telemetry
    :telemetry.execute(
      [:jido_system, :task, :processing],
      %{
        progress: 0
      },
      %{
        task_id: params.task_id,
        task_type: params.task_type
      }
    )

    # Route to specific task processor based on task_type
    case params.task_type do
      :data_processing ->
        process_data_task(params, context)

      :validation ->
        process_validation_task(params, context)

      :transformation ->
        process_transformation_task(params, context)

      :analysis ->
        process_analysis_task(params, context)

      :notification ->
        process_notification_task(params, context)

      _ ->
        {:error, {:unsupported_task_type, params.task_type}}
    end
  end

  defp process_data_task(params, _context) do
    input_data = params.input_data

    # Simulate data processing with progress updates
    steps = [
      {:validate_input, 20},
      {:load_data, 40},
      {:process_data, 70},
      {:save_results, 90},
      {:cleanup, 100}
    ]

    Enum.reduce_while(steps, {:ok, %{}}, fn {step, progress}, {:ok, acc} ->
      # Emit progress
      :telemetry.execute(
        [:jido_system, :task, :processing],
        %{
          progress: progress
        },
        %{
          task_id: params.task_id,
          step: step
        }
      )

      case step do
        :validate_input ->
          if map_size(input_data) > 0 do
            {:cont, {:ok, Map.put(acc, :validation, :passed)}}
          else
            {:halt, {:error, :empty_input_data}}
          end

        :load_data ->
          {:cont, {:ok, Map.put(acc, :data_loaded, true)}}

        :process_data ->
          processed = Map.put(input_data, :processed_at, DateTime.utc_now())
          {:cont, {:ok, Map.put(acc, :processed_data, processed)}}

        :save_results ->
          {:cont, {:ok, Map.put(acc, :saved, true)}}

        :cleanup ->
          {:cont, {:ok, Map.put(acc, :cleanup_completed, true)}}
      end
    end)
  end

  defp process_validation_task(params, _context) do
    input_data = params.input_data

    validations = [
      {:required_fields,
       fn data ->
         required = Map.get(params.options, :required_fields, [])
         Enum.all?(required, &Map.has_key?(data, &1))
       end},
      {:data_types,
       fn data ->
         # Simple type validation
         Enum.all?(data, fn {_k, v} -> not is_nil(v) end)
       end},
      {:business_rules,
       fn data ->
         # Custom business rule validation
         case Map.get(data, :amount) do
           amount when is_number(amount) and amount > 0 -> true
           # Skip if no amount field
           _ -> true
         end
       end}
    ]

    results =
      Enum.map(validations, fn {rule, validator} ->
        {rule, validator.(input_data)}
      end)

    failed_validations = Enum.filter(results, fn {_, passed} -> not passed end)

    if Enum.empty?(failed_validations) do
      {:ok,
       %{
         validation_results: results,
         status: :valid,
         validated_data: input_data
       }}
    else
      {:error, {:validation_failed, failed_validations}}
    end
  end

  defp process_transformation_task(params, _context) do
    input_data = params.input_data
    transformations = Map.get(params.options, :transformations, [])

    try do
      transformed_data =
        Enum.reduce(transformations, input_data, fn transform, data ->
          apply_transformation(transform, data)
        end)

      {:ok,
       %{
         original_data: input_data,
         transformed_data: transformed_data,
         transformations_applied: transformations
       }}
    rescue
      e ->
        {:error, {:transformation_failed, e}}
    end
  end

  defp process_analysis_task(params, _context) do
    input_data = params.input_data
    analysis_type = Map.get(params.options, :analysis_type, :basic)

    case analysis_type do
      :basic ->
        analysis = %{
          record_count: map_size(input_data),
          has_required_fields: check_required_fields(input_data),
          data_quality_score: calculate_data_quality(input_data)
        }

        {:ok, analysis}

      :advanced ->
        analysis = %{
          statistical_summary: generate_statistics(input_data),
          anomalies_detected: detect_anomalies(input_data),
          recommendations: generate_recommendations(input_data)
        }

        {:ok, analysis}

      _ ->
        {:error, {:unsupported_analysis_type, analysis_type}}
    end
  end

  defp process_notification_task(params, _context) do
    recipients = Map.get(params.options, :recipients, [])
    message = Map.get(params.options, :message, "Task notification")

    # Simulate sending notifications
    results =
      Enum.map(recipients, fn recipient ->
        # In a real implementation, this would send actual notifications
        Logger.info("Sending notification", recipient: recipient, message: message)
        {recipient, :sent}
      end)

    {:ok,
     %{
       notification_results: results,
       sent_count: length(results),
       message: message,
       task_id: params.task_id,
       sent_at: DateTime.utc_now()
     }}
  end

  defp apply_transformation(:uppercase_strings, data) do
    Enum.map(data, fn {k, v} ->
      if is_binary(v) do
        {k, String.upcase(v)}
      else
        {k, v}
      end
    end)
    |> Map.new()
  end

  defp apply_transformation(:add_timestamp, data) do
    Map.put(data, :transformed_at, DateTime.utc_now())
  end

  defp apply_transformation(transform, data) do
    Logger.warning("Unknown transformation", transform: transform)
    data
  end

  defp check_required_fields(data) do
    # Basic check for common required fields
    required = [:id, :type, :status]
    Enum.count(required, &Map.has_key?(data, &1)) / length(required)
  end

  defp calculate_data_quality(data) do
    # Simple data quality scoring
    total_fields = map_size(data)
    non_nil_fields = Enum.count(data, fn {_, v} -> not is_nil(v) end)

    if total_fields > 0 do
      non_nil_fields / total_fields * 100
    else
      0
    end
  end

  defp generate_statistics(data) do
    %{
      total_fields: map_size(data),
      field_types: Enum.map(data, fn {k, v} -> {k, typeof(v)} end) |> Map.new(),
      numeric_fields: Enum.filter(data, fn {_, v} -> is_number(v) end) |> length(),
      string_fields: Enum.filter(data, fn {_, v} -> is_binary(v) end) |> length()
    }
  end

  defp detect_anomalies(data) do
    # Simple anomaly detection
    anomalies = []

    # Check for unusual values
    anomalies =
      Enum.reduce(data, anomalies, fn {k, v}, acc ->
        cond do
          is_binary(v) and String.length(v) > 1000 ->
            [{:long_string, k, String.length(v)} | acc]

          is_number(v) and v < 0 and String.contains?(to_string(k), "count") ->
            [{:negative_count, k, v} | acc]

          true ->
            acc
        end
      end)

    anomalies
  end

  defp generate_recommendations(data) do
    recommendations = []

    # Generate based on data analysis
    recommendations =
      if map_size(data) == 0 do
        ["Add data fields to improve processing" | recommendations]
      else
        recommendations
      end

    recommendations =
      if Enum.any?(data, fn {_, v} -> is_nil(v) end) do
        ["Consider removing or filling nil values" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp typeof(value) when is_integer(value), do: :integer
  defp typeof(value) when is_float(value), do: :float
  defp typeof(value) when is_binary(value), do: :string
  defp typeof(value) when is_boolean(value), do: :boolean
  defp typeof(value) when is_atom(value), do: :atom
  defp typeof(value) when is_list(value), do: :list
  defp typeof(value) when is_map(value), do: :map
  defp typeof(_), do: :unknown
end
