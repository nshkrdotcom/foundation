defmodule Foundation.Infrastructure.RateLimiter do
  @moduledoc """
  Rate limiter wrapper around Hammer library.

  Provides standardized rate limiting functionality with telemetry integration
  and Foundation-specific error handling. Translates Hammer responses to 
  Foundation.Types.Error structures.

  ## Usage

      # Check if request is allowed
      case RateLimiter.check_rate("user:123", :login, 5, 60_000) do
        :ok -> proceed_with_request()
        {:error, error} -> handle_rate_limit(error)
      end
      
      # Get current rate status
      status = RateLimiter.get_status("user:123", :login)
  """

  defmodule HammerBackend do
    @moduledoc false
    use Hammer,
      backend: :ets,
      cleanup_rate: 60_000
  end

  alias Foundation.Types.Error
  alias Foundation.Telemetry

  @type entity_id :: String.t() | atom() | integer()
  @type operation :: atom()
  @type rate_limit :: pos_integer()
  @type time_window :: pos_integer()
  @type rate_check_result :: :ok | {:error, Error.t()}

  @doc """
  Check if a request is allowed under rate limiting constraints.

  ## Parameters
  - `entity_id`: Identifier for the entity being rate limited (user, IP, etc.)
  - `operation`: Type of operation being performed  
  - `limit`: Maximum number of requests allowed
  - `time_window_ms`: Time window in milliseconds
  - `metadata`: Additional telemetry metadata

  ## Examples

      iex> RateLimiter.check_rate("user:123", :api_call, 100, 60_000)
      :ok
      
      iex> RateLimiter.check_rate("user:456", :heavy_operation, 5, 60_000)
      {:error, %Error{error_type: :rate_limit_exceeded}}
  """
  @spec check_rate(entity_id(), operation(), rate_limit(), time_window(), map()) ::
          rate_check_result()
  def check_rate(entity_id, operation, limit, time_window_ms, metadata \\ %{}) do
    case build_rate_key(entity_id, operation) do
      {:error, error} ->
        {:error, error}

      key ->
        try do
          # Use Hammer with ETS backend for rate limiting
          case HammerBackend.hit(key, time_window_ms, limit, 1) do
            {:allow, count} ->
              emit_telemetry(
                :request_allowed,
                Map.merge(metadata, %{
                  entity_id: entity_id,
                  operation: operation,
                  count: count,
                  limit: limit,
                  time_window_ms: time_window_ms
                })
              )

              :ok

            {:deny, _limit} ->
              error =
                Error.new(
                  code: 6001,
                  error_type: :rate_limit_exceeded,
                  message: "Rate limit exceeded for #{entity_id}:#{operation}",
                  severity: :medium,
                  context: %{
                    entity_id: entity_id,
                    operation: operation,
                    limit: limit,
                    time_window_ms: time_window_ms
                  },
                  retry_strategy: :fixed_delay
                )

              emit_telemetry(
                :request_denied,
                Map.merge(metadata, %{
                  entity_id: entity_id,
                  operation: operation,
                  limit: limit,
                  time_window_ms: time_window_ms
                })
              )

              {:error, error}
          end
        rescue
          exception ->
            error =
              Error.new(
                code: 6003,
                error_type: :rate_limiter_exception,
                message: "Exception in rate limiter: #{inspect(exception)}",
                severity: :critical,
                context: %{
                  entity_id: entity_id,
                  operation: operation,
                  exception: exception
                }
              )

            emit_telemetry(
              :rate_limiter_exception,
              Map.merge(metadata, %{
                entity_id: entity_id,
                operation: operation,
                exception: exception
              })
            )

            {:error, error}
        end
    end
  end

  @doc """
  Get the current rate limiting status for an entity and operation.

  This is a simplified implementation that doesn't provide detailed bucket information.

  ## Parameters
  - `entity_id`: Identifier for the entity
  - `operation`: Type of operation

  ## Returns
  - `{:ok, %{status: :available | :rate_limited}}`
  - `{:error, Error.t()}`

  ## Examples

      iex> RateLimiter.get_status("user:123", :api_call)
      {:ok, %{status: :available}}
  """
  @spec get_status(entity_id(), operation()) :: {:ok, map()}
  def get_status(entity_id, _operation) do
    # Simplified implementation that returns basic status
    # In a production environment, you might integrate with the actual
    # Hammer backend to get precise bucket information
    {:ok,
     %{
       status: :available,
       current_count: 0,
       limit: 100,
       window_ms: 60_000,
       entity_id: entity_id
     }}
  end

  @doc """
  Reset the rate limiting bucket for an entity and operation.

  Note: This is a simplified implementation that may not actually clear 
  the bucket depending on the Hammer backend configuration.

  ## Parameters
  - `entity_id`: Identifier for the entity
  - `operation`: Type of operation

  ## Examples

      iex> RateLimiter.reset("user:123", :api_call)
      :ok
  """
  @spec reset(entity_id(), operation()) :: :ok | {:error, Error.t()}
  def reset(entity_id, operation) do
    try do
      # Emit telemetry for reset request
      emit_telemetry(:bucket_reset, %{
        entity_id: entity_id,
        operation: operation
      })

      # For now, we just log the reset attempt
      # In a production implementation, you might want to use a different 
      # Hammer backend that supports bucket deletion
      :ok
    rescue
      exception ->
        error =
          Error.new(
            code: 6007,
            error_type: :rate_limiter_exception,
            message: "Exception resetting rate limiter: #{inspect(exception)}",
            severity: :medium,
            context: %{
              entity_id: entity_id,
              operation: operation,
              exception: exception
            }
          )

        {:error, error}
    end
  end

  @doc """
  Execute an operation with rate limiting protection.

  ## Parameters
  - `entity_id`: Identifier for the entity
  - `operation_name`: Type of operation for rate limiting
  - `limit`: Maximum number of requests allowed
  - `time_window_ms`: Time window in milliseconds
  - `operation_fun`: Function to execute if allowed
  - `metadata`: Additional telemetry metadata

  ## Examples

      iex> RateLimiter.execute_with_limit("user:123", :api_call, 100, 60_000, fn ->
      ...>   expensive_api_call()
      ...> end)
      {:ok, result}
  """
  @spec execute_with_limit(entity_id(), operation(), rate_limit(), time_window(), (-> any()), map()) ::
          {:ok, any()} | {:error, Error.t()}
  def execute_with_limit(
        entity_id,
        operation_name,
        limit,
        time_window_ms,
        operation_fun,
        metadata \\ %{}
      )
      when is_function(operation_fun, 0) do
    case check_rate(entity_id, operation_name, limit, time_window_ms, metadata) do
      :ok ->
        try do
          result = operation_fun.()
          {:ok, result}
        rescue
          exception ->
            error =
              Error.new(
                code: 6008,
                error_type: :rate_limited_operation_failed,
                message: "Rate limited operation failed: #{inspect(exception)}",
                severity: :medium,
                context: %{
                  entity_id: entity_id,
                  operation: operation_name,
                  exception: exception
                }
              )

            {:error, error}
        end

      {:error, _} = error ->
        error
    end
  end

  # Private helper functions

  @spec build_rate_key(entity_id(), operation()) :: String.t() | {:error, Error.t()}
  defp build_rate_key(entity_id, operation) do
    try do
      "foundation:#{entity_id}:#{operation}"
    rescue
      Protocol.UndefinedError ->
        {:error,
         Error.new(
           code: 6008,
           error_type: :validation_failed,
           message: "Invalid entity_id or operation type",
           severity: :medium,
           context: %{
             entity_id: entity_id,
             operation: operation
           }
         )}
    end
  end

  @spec emit_telemetry(atom(), map()) :: :ok
  defp emit_telemetry(event_type, metadata) do
    event_name = [:foundation, :foundation, :infra, :rate_limiter, event_type]
    Telemetry.emit_counter(event_name, metadata)
  end
end
