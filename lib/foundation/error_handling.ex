defmodule Foundation.ErrorHandling do
  @moduledoc """
  Standardized error handling patterns for Foundation services.

  This module provides consistent error handling utilities to address
  the mixed error patterns throughout the codebase. All Foundation
  services should use these patterns for consistency.

  ## Error Tuple Format

  All errors should follow the format:
  - `{:error, atom}` for simple errors
  - `{:error, {atom, details}}` for errors with additional context

  ## Exception Handling

  Use the provided macros to handle exceptions consistently:
  - `safe_call/2` - Wraps operations that might raise
  - `safe_rescue/3` - Rescues specific exceptions
  """

  # Standard error types used across Foundation services.
  @type error_reason ::
          :not_found
          | :already_exists
          | :invalid_config
          | :unavailable
          | :timeout
          | {:invalid_field, atom()}
          | {:missing_field, atom()}
          | {:service_error, atom(), term()}
          | {:exception, Exception.t()}

  @type error :: {:error, error_reason()}
  @type result(t) :: {:ok, t} | error()

  @doc """
  Safely executes a function and converts exceptions to error tuples.

  ## Examples

      safe_call do
        risky_operation()
      end
      # => {:ok, result} or {:error, {:exception, %RuntimeError{...}}}
  """
  defmacro safe_call(do: block) do
    quote do
      try do
        result = unquote(block)
        {:ok, result}
      rescue
        exception ->
          {:error, {:exception, exception}}
      end
    end
  end

  @doc """
  Safely executes a function with custom error handling.

  ## Examples

      safe_call fn -> risky_operation() end,
        ArgumentError -> {:error, :invalid_argument}
  """
  defmacro safe_call(fun, rescue_clauses) do
    quote do
      try do
        result = unquote(fun).()
        {:ok, result}
      rescue
        unquote(rescue_clauses)
      end
    end
  end

  @doc """
  Wraps telemetry emissions to never fail.

  Telemetry should never cause application failures.
  """
  @spec emit_telemetry_safe(atom() | [atom()], map(), map()) :: :ok
  def emit_telemetry_safe(event, measurements, metadata) do
    Foundation.Telemetry.emit(event, measurements, metadata)
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Standardizes error responses for missing configuration fields.
  """
  @spec missing_field_error(atom()) :: error()
  def missing_field_error(field) do
    {:error, {:missing_field, field}}
  end

  @doc """
  Standardizes error responses for invalid configuration fields.
  """
  @spec invalid_field_error(atom(), term()) :: error()
  def invalid_field_error(field, reason \\ nil) do
    case reason do
      nil -> {:error, {:invalid_field, field}}
      _ -> {:error, {:invalid_field, field, reason}}
    end
  end

  @doc """
  Standardizes service unavailable errors.
  """
  @spec service_unavailable_error(atom()) :: error()
  def service_unavailable_error(service) do
    {:error, {:service_error, service, :unavailable}}
  end

  @doc """
  Converts exceptions to standardized error tuples.
  """
  @spec exception_to_error(Exception.t()) :: error()
  def exception_to_error(exception) do
    {:error, {:exception, exception}}
  end

  @doc """
  Chains operations that return {:ok, value} or {:error, reason}.

  ## Examples

      with_ok do
        user <- get_user(id)
        profile <- get_profile(user.id)
        {:ok, profile}
      end
  """
  defmacro with_ok(do: block) do
    quote do
      with unquote(block)
    end
  end

  @doc """
  Ensures consistent error logging format.
  """
  @spec log_error(String.t(), error(), Keyword.t()) :: :ok
  def log_error(message, {:error, reason}, metadata \\ []) do
    require Logger
    Logger.error("#{message}: #{inspect(reason)}", metadata)
    :ok
  end

  @doc """
  Normalizes different error formats to standard format.

  Useful when integrating with third-party libraries.
  """
  @spec normalize_error(term()) :: error()
  def normalize_error({:error, _} = error), do: error
  def normalize_error(:error), do: {:error, :unknown}
  def normalize_error(other), do: {:error, {:unexpected, other}}
end
