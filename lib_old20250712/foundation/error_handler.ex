defmodule Foundation.ErrorHandler do
  @moduledoc """
  Advanced error handling for Foundation operations.

  Provides standardized error types, recovery strategies, circuit breaker
  integration, and comprehensive error telemetry.

  ## Error Categories

  - `:transient` - Temporary errors that may succeed on retry
  - `:permanent` - Errors that will not succeed on retry
  - `:resource` - Resource exhaustion or limit errors
  - `:validation` - Input validation errors
  - `:system` - System-level errors (process crashes, etc.)

  ## Recovery Strategies

  - `:retry` - Retry with exponential backoff
  - `:circuit_break` - Open circuit breaker to prevent cascading failures
  - `:fallback` - Use fallback value or behavior
  - `:propagate` - Propagate error to caller
  - `:compensate` - Run compensation logic
  """

  require Logger

  # Standard error structure
  defmodule Error do
    @moduledoc """
    Standardized error structure for Foundation.
    """

    @enforce_keys [:category, :reason]
    defstruct [
      :category,
      :reason,
      :context,
      :stacktrace,
      :timestamp,
      :retry_count,
      :recovery_strategy
    ]

    @type error_category :: :transient | :permanent | :resource | :validation | :system
    @type recovery_strategy :: :retry | :circuit_break | :fallback | :propagate | :compensate | nil

    @type t :: %__MODULE__{
            category: error_category(),
            reason: term(),
            context: map() | nil,
            stacktrace: list() | nil,
            timestamp: DateTime.t(),
            retry_count: non_neg_integer(),
            recovery_strategy: recovery_strategy()
          }
  end

  # Recovery strategies
  @recovery_strategies %{
    # Error category -> default strategy
    transient: :retry,
    permanent: :propagate,
    resource: :circuit_break,
    validation: :propagate,
    system: :compensate
  }

  # Retry configuration
  @max_retries 3
  @base_backoff_ms 100
  @max_backoff_ms 5000

  @doc """
  Wraps a function with error handling and recovery.

  ## Options

  - `:category` - Error category (defaults to :transient)
  - `:strategy` - Recovery strategy (defaults based on category)
  - `:max_retries` - Maximum retry attempts
  - `:circuit_breaker` - Circuit breaker name
  - `:fallback` - Fallback value or function
  - `:telemetry_metadata` - Additional telemetry metadata

  ## Examples

      # Simple retry on error
      ErrorHandler.with_recovery(fn ->
        risky_operation()
      end)

      # With fallback
      ErrorHandler.with_recovery(fn ->
        fetch_from_api()
      end, fallback: {:ok, default_value})

      # With circuit breaker
      ErrorHandler.with_recovery(fn ->
        external_service_call()
      end, circuit_breaker: :external_api)
  """
  def with_recovery(fun, opts \\ []) when is_function(fun, 0) do
    category = Keyword.get(opts, :category, :transient)
    strategy = Keyword.get(opts, :strategy, @recovery_strategies[category])
    max_retries = Keyword.get(opts, :max_retries, @max_retries)

    execute_with_recovery(fun, strategy, opts, 0, max_retries)
  end

  @doc """
  Creates a standardized error.
  """
  def create_error(category, reason, context \\ %{}) do
    %Error{
      category: category,
      reason: reason,
      context: context,
      timestamp: DateTime.utc_now(),
      retry_count: 0,
      stacktrace: nil
    }
  end

  @doc """
  Wraps an error with additional context.
  """
  def wrap_error(error, additional_context) when is_map(additional_context) do
    case error do
      %Error{} = e ->
        %{e | context: Map.merge(e.context || %{}, additional_context)}

      other ->
        create_error(:system, other, additional_context)
    end
  end

  @doc """
  Determines if an error is retryable based on its category.
  """
  def retryable?(%Error{category: category}) do
    category in [:transient, :resource]
  end

  def retryable?(_), do: false

  @doc """
  Registers a custom recovery strategy.
  """
  def register_recovery_strategy(name, handler) when is_atom(name) and is_function(handler) do
    # In a real implementation, this would use a Registry or ETS table
    # For now, we'll log it
    Logger.info("Registered recovery strategy: #{name}")
  end

  # Private functions

  defp execute_with_recovery(fun, :retry, opts, retry_count, max_retries) do
    start_time = System.monotonic_time(:microsecond)

    case safe_execute(fun) do
      {:ok, result} ->
        emit_success_telemetry(start_time, retry_count, opts)
        {:ok, result}

      {:error, error} when retry_count < max_retries ->
        error = increment_retry_count(error)

        if retryable?(error) do
          backoff = calculate_backoff(retry_count)

          Logger.debug("""
          Retrying after error: #{inspect(error.reason)}
          Retry attempt: #{retry_count + 1}/#{max_retries}
          Backoff: #{backoff}ms
          """)

          emit_retry_telemetry(error, retry_count, backoff, opts)

          Process.sleep(backoff)
          execute_with_recovery(fun, :retry, opts, retry_count + 1, max_retries)
        else
          emit_error_telemetry(error, start_time, opts)
          {:error, error}
        end

      {:error, error} ->
        emit_error_telemetry(error, start_time, opts)
        handle_max_retries_exceeded(error, opts)
    end
  end

  defp execute_with_recovery(fun, :circuit_break, opts, retry_count, _max_retries) do
    breaker_name = Keyword.get(opts, :circuit_breaker, :default)

    case check_circuit_breaker(breaker_name) do
      :open ->
        error = create_error(:resource, :circuit_breaker_open, %{breaker: breaker_name})
        emit_error_telemetry(error, System.monotonic_time(:microsecond), opts)
        handle_fallback({:error, error}, opts)

      :closed ->
        start_time = System.monotonic_time(:microsecond)

        case safe_execute(fun) do
          {:ok, result} ->
            emit_success_telemetry(start_time, retry_count, opts)
            record_circuit_breaker_success(breaker_name)
            {:ok, result}

          {:error, error} ->
            emit_error_telemetry(error, start_time, opts)
            record_circuit_breaker_failure(breaker_name)
            handle_fallback({:error, error}, opts)
        end
    end
  end

  defp execute_with_recovery(fun, :fallback, opts, _retry_count, _max_retries) do
    start_time = System.monotonic_time(:microsecond)

    case safe_execute(fun) do
      {:ok, result} ->
        emit_success_telemetry(start_time, 0, opts)
        {:ok, result}

      {:error, error} ->
        emit_error_telemetry(error, start_time, opts)
        handle_fallback({:error, error}, opts)
    end
  end

  defp execute_with_recovery(fun, :propagate, opts, _retry_count, _max_retries) do
    start_time = System.monotonic_time(:microsecond)

    case safe_execute(fun) do
      {:ok, result} ->
        emit_success_telemetry(start_time, 0, opts)
        {:ok, result}

      {:error, error} ->
        emit_error_telemetry(error, start_time, opts)
        handle_fallback({:error, error}, opts)
    end
  end

  defp execute_with_recovery(fun, :compensate, opts, _retry_count, _max_retries) do
    start_time = System.monotonic_time(:microsecond)

    case safe_execute(fun) do
      {:ok, result} ->
        emit_success_telemetry(start_time, 0, opts)
        {:ok, result}

      {:error, error} ->
        emit_error_telemetry(error, start_time, opts)

        # Run compensation if provided
        case Keyword.get(opts, :compensation) do
          nil ->
            {:error, error}

          compensation when is_function(compensation, 1) ->
            Logger.info("Running compensation logic for error: #{inspect(error.reason)}")
            compensation.(error)
            {:error, error}
        end
    end
  end

  # DEPRECATED: This function caught all errors, preventing "let it crash"
  # Use specific error handlers instead
  @deprecated "Use handle_network_error/1, handle_database_error/1, or handle_validation_error/1 instead"
  defp safe_execute(fun) do
    # For backward compatibility with existing tests
    try do
      case fun.() do
        :ok -> {:ok, :ok}
        {:ok, _} = ok -> ok
        {:error, _} = error -> error
        other -> {:ok, other}
      end
    rescue
      exception ->
        {:error,
         create_error(:system, exception, %{
           message: Exception.message(exception),
           stacktrace: __STACKTRACE__
         })}
    catch
      kind, reason ->
        {:error,
         create_error(:system, {kind, reason}, %{
           caught: kind,
           stacktrace: __STACKTRACE__
         })}
    end
  end

  @doc """
  Handles network-related errors specifically.
  Only catches expected network exceptions.
  """
  def handle_network_error(fun) when is_function(fun, 0) do
    fun.()
  rescue
    error ->
      # Check if the error is a known network error type
      if is_network_error?(error) do
        {:error,
         create_error(:transient, error, %{
           type: :network_error,
           message: Exception.message(error)
         })}
      else
        # Re-raise if not a network error
        reraise error, __STACKTRACE__
      end
  end

  # Helper function to check network errors without compile-time dependencies
  defp is_network_error?(error) when is_exception(error) do
    module = error.__struct__
    # Check for common network error modules dynamically
    module_name = Module.split(module) |> List.last()

    module_name in ["HTTPError", "Error"] or
      module == :hackney_error or
      (Code.ensure_loaded?(Mint.HTTPError) and module == Mint.HTTPError) or
      (Code.ensure_loaded?(Finch.Error) and module == Finch.Error)
  end

  defp is_network_error?(_), do: false

  @doc """
  Handles database-related errors specifically.
  Only catches expected database exceptions.
  """
  def handle_database_error(fun) when is_function(fun, 0) do
    fun.()
  rescue
    error ->
      # Check if the error is a known database error type
      if is_database_error?(error) do
        {:error,
         create_error(:transient, error, %{
           type: :database_error,
           message: Exception.message(error)
         })}
      else
        # Re-raise if not a database error
        reraise error, __STACKTRACE__
      end
  end

  # Helper function to check database errors without compile-time dependencies
  defp is_database_error?(error) when is_exception(error) do
    module = error.__struct__
    # Check for common database error modules dynamically
    module_name = Module.split(module) |> List.last()

    module_name in ["ConnectionError", "Error", "CastError"] or
      (Code.ensure_loaded?(DBConnection.ConnectionError) and
         module == DBConnection.ConnectionError) or
      (Code.ensure_loaded?(Postgrex.Error) and module == Postgrex.Error) or
      (Code.ensure_loaded?(Ecto.Query.CastError) and module == Ecto.Query.CastError)
  end

  defp is_database_error?(_), do: false

  @doc """
  Handles validation errors specifically.
  These are usually permanent errors that won't succeed on retry.
  """
  def handle_validation_error(fun) when is_function(fun, 0) do
    fun.()
  rescue
    error in [ArgumentError, FunctionClauseError] ->
      {:error,
       create_error(:validation, error, %{
         type: :validation_error,
         message: Exception.message(error)
       })}
  end

  defp increment_retry_count(%Error{} = error) do
    %{error | retry_count: error.retry_count + 1}
  end

  defp increment_retry_count(error) do
    create_error(:system, error, %{retry_count: 1})
  end

  defp calculate_backoff(retry_count) do
    backoff = @base_backoff_ms * :math.pow(2, retry_count)
    jitter = :rand.uniform(100)

    min(trunc(backoff + jitter), @max_backoff_ms)
  end

  defp handle_max_retries_exceeded(error, opts) do
    case Keyword.get(opts, :fallback) do
      nil ->
        {:error, %{error | recovery_strategy: :max_retries_exceeded}}

      _fallback ->
        handle_fallback({:error, error}, opts)
    end
  end

  defp handle_fallback({:error, error}, opts) do
    case Keyword.get(opts, :fallback) do
      nil ->
        {:error, error}

      {:ok, value} ->
        {:ok, value}

      fun when is_function(fun, 0) ->
        safe_execute(fun)

      fun when is_function(fun, 1) ->
        fun.(error)
    end
  end

  # Circuit breaker helpers using ETS for atomic operations
  @circuit_breaker_table :foundation_circuit_breakers

  defp ensure_circuit_breaker_table do
    case :ets.whereis(@circuit_breaker_table) do
      :undefined ->
        # Create table if it doesn't exist (race-safe)
        try do
          :ets.new(@circuit_breaker_table, [:named_table, :public, :set])
        rescue
          # Table already exists
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp check_circuit_breaker(name) do
    ensure_circuit_breaker_table()

    case :ets.lookup(@circuit_breaker_table, name) do
      [{^name, state, _failure_count, opened_at}] when state == :open ->
        # Check if enough time has passed to half-open
        if System.monotonic_time(:second) - opened_at > 30 do
          # Allow one request through
          :closed
        else
          :open
        end

      _ ->
        :closed
    end
  end

  defp record_circuit_breaker_success(name) do
    ensure_circuit_breaker_table()

    # Atomically reset the circuit breaker
    :ets.insert(@circuit_breaker_table, {name, :closed, 0, 0})
  end

  defp record_circuit_breaker_failure(name) do
    ensure_circuit_breaker_table()

    # Atomically increment failure count
    failure_count =
      case :ets.update_counter(@circuit_breaker_table, name, {3, 1}, {name, :closed, 0, 0}) do
        count when is_integer(count) -> count
        _ -> 1
      end

    if failure_count >= 5 do
      # Open the circuit atomically
      :ets.insert(
        @circuit_breaker_table,
        {name, :open, failure_count, System.monotonic_time(:second)}
      )
    end
  end

  # Telemetry helpers

  defp emit_success_telemetry(start_time, retry_count, opts) do
    duration = System.monotonic_time(:microsecond) - start_time
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    :telemetry.execute(
      [:foundation, :error_handler, :success],
      %{duration: duration, retry_count: retry_count},
      metadata
    )
  end

  defp emit_retry_telemetry(%Error{} = error, retry_count, backoff, opts) do
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    :telemetry.execute(
      [:foundation, :error_handler, :retry],
      %{retry_count: retry_count, backoff_ms: backoff},
      Map.merge(metadata, %{
        error_category: error.category,
        error_reason: error.reason
      })
    )
  end

  defp emit_error_telemetry(%Error{} = error, start_time, opts) do
    duration = System.monotonic_time(:microsecond) - start_time
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    :telemetry.execute(
      [:foundation, :error_handler, :error],
      %{duration: duration, retry_count: error.retry_count},
      Map.merge(metadata, %{
        error_category: error.category,
        error_reason: error.reason,
        recovery_strategy: error.recovery_strategy
      })
    )
  end

  defp emit_error_telemetry(error, start_time, opts) do
    duration = System.monotonic_time(:microsecond) - start_time
    metadata = Keyword.get(opts, :telemetry_metadata, %{})

    :telemetry.execute(
      [:foundation, :error_handler, :error],
      %{duration: duration, retry_count: 0},
      Map.merge(metadata, %{
        error_category: :unknown,
        error_reason: error,
        recovery_strategy: nil
      })
    )
  end
end
