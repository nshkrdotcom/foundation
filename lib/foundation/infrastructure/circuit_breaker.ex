defmodule Foundation.Infrastructure.CircuitBreaker do
  @moduledoc """
  Circuit breaker wrapper around :fuse library.

  Provides standardized circuit breaker functionality with telemetry integration
  and Foundation-specific error handling. Translates :fuse errors to
  Foundation.Types.Error structures.

  ## Usage

      # Start a fuse instance
      {:ok, _pid} = CircuitBreaker.start_fuse_instance(:my_service, options)

      # Execute protected operation
      case CircuitBreaker.execute(:my_service, fn -> risky_operation() end) do
        {:ok, result} -> result
        {:error, error} -> handle_error(error)
      end

      # Check circuit status
      status = CircuitBreaker.get_status(:my_service)
  """

  alias Foundation.Telemetry
  alias Foundation.Types.Error

  @type fuse_name :: atom()
  @type fuse_options :: [
          strategy: :standard | :fault_injection,
          tolerance: non_neg_integer(),
          refresh: non_neg_integer()
        ]
  @type operation :: (-> any())
  @type operation_result :: {:ok, any()} | {:error, Error.t()}

  @doc """
  Start a new fuse instance with the given name and options.

  ## Parameters
  - `name`: Unique atom identifier for the fuse
  - `options`: Fuse configuration options

  ## Examples

      iex> CircuitBreaker.start_fuse_instance(:database,
      ...>   strategy: :standard, tolerance: 5, refresh: 60_000)
      {:ok, #PID<0.123.0>}
  """
  @spec start_fuse_instance(fuse_name(), fuse_options()) :: :ok | {:error, Error.t()}
  def start_fuse_instance(name, options \\ []) when is_atom(name) do
    default_options = {{:standard, 5, 60_000}, {:reset, 60_000}}

    fuse_options =
      case options do
        [] ->
          default_options

        [strategy: :standard, tolerance: tolerance, refresh: refresh] ->
          {{:standard, tolerance, refresh}, {:reset, refresh}}

        _ ->
          default_options
      end

    try do
      case :fuse.install(name, fuse_options) do
        :ok ->
          emit_telemetry(:fuse_installed, %{name: name, options: fuse_options})
          :ok

        {:error, :already_installed} ->
          emit_telemetry(:fuse_already_installed, %{name: name})
          :ok

        {:error, reason} ->
          error =
            Error.new(
              code: 5001,
              error_type: :circuit_breaker_install_failed,
              message: "Failed to install circuit breaker: #{inspect(reason)}",
              severity: :high,
              context: %{fuse_name: name, reason: reason}
            )

          emit_telemetry(:fuse_install_failed, %{name: name, reason: reason})
          {:error, error}
      end
    rescue
      exception ->
        error =
          Error.new(
            code: 5002,
            error_type: :circuit_breaker_exception,
            message: "Exception during fuse installation: #{inspect(exception)}",
            severity: :critical,
            context: %{fuse_name: name, exception: exception}
          )

        emit_telemetry(:fuse_install_exception, %{name: name, exception: exception})
        {:error, error}
    end
  end

  @doc """
  Execute an operation protected by the circuit breaker.

  ## Parameters
  - `name`: Fuse instance name
  - `operation`: Function to execute
  - `metadata`: Additional telemetry metadata

  ## Examples

      iex> CircuitBreaker.execute(:database, fn -> DB.query("SELECT 1") end)
      {:ok, [%{column: 1}]}

      iex> CircuitBreaker.execute(:failing_service, fn -> raise "boom" end)
      {:error, %Error{error_type: :circuit_breaker_blown}}
  """
  @spec execute(fuse_name(), operation(), map()) :: operation_result()
  def execute(name, operation, metadata \\ %{})

  def execute(name, operation, metadata) when is_atom(name) and is_function(operation, 0) do
    start_time = System.monotonic_time(:microsecond)

    try do
      case :fuse.ask(name, :sync) do
        :ok ->
          # Circuit is closed, execute operation
          try do
            result = operation.()
            duration = System.monotonic_time(:microsecond) - start_time

            emit_telemetry(
              :call_executed,
              Map.merge(metadata, %{
                name: name,
                duration: duration,
                status: :success
              })
            )

            {:ok, result}
          rescue
            exception ->
              # Operation failed, melt the fuse
              :fuse.melt(name)
              duration = System.monotonic_time(:microsecond) - start_time

              error =
                Error.new(
                  code: 5003,
                  error_type: :protected_operation_failed,
                  message: "Protected operation failed: #{inspect(exception)}",
                  severity: :medium,
                  context: %{fuse_name: name, exception: exception}
                )

              emit_telemetry(
                :call_executed,
                Map.merge(metadata, %{
                  name: name,
                  duration: duration,
                  status: :failed,
                  exception: exception
                })
              )

              {:error, error}
          catch
            kind, value ->
              # Handle throw and exit
              :fuse.melt(name)
              duration = System.monotonic_time(:microsecond) - start_time

              error =
                Error.new(
                  code: 5012,
                  error_type: :protected_operation_failed,
                  message: "Protected operation failed with #{kind}: #{inspect(value)}",
                  severity: :medium,
                  context: %{fuse_name: name, kind: kind, value: value}
                )

              emit_telemetry(
                :call_executed,
                Map.merge(metadata, %{
                  name: name,
                  duration: duration,
                  status: :failed,
                  kind: kind,
                  value: value
                })
              )

              {:error, error}
          end

        :blown ->
          # Circuit is open
          error =
            Error.new(
              code: 5004,
              error_type: :circuit_breaker_blown,
              message: "Circuit breaker is open for #{name}",
              severity: :medium,
              context: %{fuse_name: name},
              retry_strategy: :fixed_delay
            )

          emit_telemetry(
            :call_rejected,
            Map.merge(metadata, %{
              name: name,
              reason: :circuit_blown
            })
          )

          {:error, error}

        {:error, :not_found} ->
          # Fuse not installed
          error =
            Error.new(
              code: 5005,
              error_type: :circuit_breaker_not_found,
              message: "Circuit breaker #{name} not found",
              severity: :high,
              context: %{fuse_name: name}
            )

          emit_telemetry(
            :call_rejected,
            Map.merge(metadata, %{
              name: name,
              reason: :not_found
            })
          )

          {:error, error}
      end
    rescue
      exception ->
        duration = System.monotonic_time(:microsecond) - start_time

        error =
          Error.new(
            code: 5006,
            error_type: :circuit_breaker_exception,
            message: "Exception in circuit breaker execution: #{inspect(exception)}",
            severity: :critical,
            context: %{fuse_name: name, exception: exception}
          )

        emit_telemetry(
          :call_executed,
          Map.merge(metadata, %{
            name: name,
            duration: duration,
            status: :exception,
            exception: exception
          })
        )

        {:error, error}
    end
  end

  def execute(name, operation, _metadata) do
    {:error,
     Error.new(
       code: 5009,
       error_type: :invalid_input,
       message:
         "Invalid circuit breaker inputs: name must be atom, operation must be 0-arity function",
       severity: :medium,
       context: %{
         name: name,
         operation_type: if(is_function(operation), do: :function, else: :not_function)
       }
     )}
  rescue
    _ ->
      {:error,
       Error.new(
         code: 5010,
         error_type: :invalid_input,
         message: "Invalid circuit breaker inputs",
         severity: :medium,
         context: %{name: name, operation: operation}
       )}
  end

  @doc """
  Get the current status of a circuit breaker.

  ## Parameters
  - `name`: Fuse instance name

  ## Returns
  - `:ok` - Circuit is closed (healthy)
  - `:blown` - Circuit is open (unhealthy)
  - `{:error, Error.t()}` - Fuse not found or other error

  ## Examples

      iex> CircuitBreaker.get_status(:my_service)
      :ok

      iex> CircuitBreaker.get_status(:blown_service)
      :blown
  """
  @spec get_status(fuse_name()) :: :ok | :blown | {:error, Error.t()}
  def get_status(name) when is_atom(name) do
    try do
      case :fuse.ask(name, :sync) do
        :ok ->
          :ok

        :blown ->
          :blown

        {:error, :not_found} ->
          error =
            Error.new(
              code: 5007,
              error_type: :circuit_breaker_not_found,
              message: "Circuit breaker #{name} not found",
              severity: :medium,
              context: %{fuse_name: name}
            )

          {:error, error}
      end
    rescue
      exception ->
        error =
          Error.new(
            code: 5008,
            error_type: :circuit_breaker_exception,
            message: "Exception checking circuit breaker status: #{inspect(exception)}",
            severity: :medium,
            context: %{fuse_name: name, exception: exception}
          )

        {:error, error}
    end
  end

  def get_status(name) do
    {:error,
     Error.new(
       code: 5011,
       error_type: :invalid_input,
       message: "Invalid circuit breaker name: must be an atom",
       severity: :medium,
       context: %{name: name}
     )}
  end

  @doc """
  Reset a blown circuit breaker manually.

  ## Parameters
  - `name`: Fuse instance name

  ## Examples

      iex> CircuitBreaker.reset(:my_service)
      :ok
  """
  @spec reset(fuse_name()) :: :ok | {:error, Error.t()}
  def reset(name) when is_atom(name) do
    try do
      case :fuse.reset(name) do
        :ok ->
          emit_telemetry(:state_change, %{name: name, new_state: :reset})
          :ok

        {:error, :not_found} ->
          error =
            Error.new(
              code: 5013,
              error_type: :circuit_breaker_not_found,
              message: "Cannot reset circuit breaker #{name}: not found",
              severity: :medium,
              context: %{fuse_name: name}
            )

          {:error, error}
      end
    rescue
      exception ->
        error =
          Error.new(
            code: 5014,
            error_type: :circuit_breaker_exception,
            message: "Exception resetting circuit breaker: #{inspect(exception)}",
            severity: :medium,
            context: %{fuse_name: name, exception: exception}
          )

        {:error, error}
    end
  end

  # Private helper functions

  @spec emit_telemetry(atom(), map()) :: :ok
  defp emit_telemetry(event_type, metadata) do
    event_name = [:foundation, :foundation, :infra, :circuit_breaker, event_type]
    Telemetry.emit_counter(event_name, metadata)
  end
end
