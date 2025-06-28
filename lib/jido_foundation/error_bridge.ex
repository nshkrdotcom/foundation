defmodule JidoFoundation.ErrorBridge do
  @moduledoc """
  Error standardization bridge between Jido and Foundation frameworks.
  
  This module provides unified error handling across Jido and Foundation,
  ensuring consistent error structures, contexts, and handling patterns.
  
  Key capabilities:
  - Automatic conversion between Jido and Foundation error formats
  - Unified error context tracking
  - Error correlation across framework boundaries
  - Structured error logging and telemetry
  - Error recovery strategy coordination
  
  ## Usage Examples
  
      # Convert Jido error to Foundation format
      jido_error = %Jido.Error{code: :validation_failed, message: "Invalid input"}
      foundation_error = ErrorBridge.normalize_jido_error(jido_error)
      
      # Handle Foundation error in Jido context
      foundation_error = %Foundation.Types.Error{...}
      jido_result = ErrorBridge.handle_foundation_error_in_jido(foundation_error)
      
      # Create unified error with context
      {:error, unified_error} = ErrorBridge.create_unified_error(
        :agent_communication_failed,
        "Agent failed to respond",
        %{agent_id: :coder, operation: :generate_code}
      )
  """

  alias Foundation.Types.Error, as: FoundationError
  require Logger

  @type error_code :: atom()
  @type error_message :: String.t()
  @type error_context :: map()
  @type error_source :: :jido | :foundation | :bridge
  @type bridge_result :: {:ok, term()} | {:error, term()}

  @type unified_error :: %{
          code: error_code(),
          message: error_message(),
          source: error_source(),
          context: error_context(),
          correlation_id: String.t(),
          timestamp: DateTime.t(),
          stack_trace: [term()],
          recovery_suggestions: [String.t()]
        }

  @type error_mapping :: %{
          jido_to_foundation: %{atom() => atom()},
          foundation_to_jido: %{atom() => atom()}
        }

  @doc """
  Normalizes a Jido error to Foundation.Types.Error format.
  
  ## Parameters
  - `jido_error`: The Jido error to convert
  - `opts`: Conversion options
  
  ## Options
  - `:preserve_context` - Preserve original error context (default: true)
  - `:add_bridge_context` - Add bridge metadata (default: true)
  - `:correlation_id` - Error correlation ID (default: generated)
  
  ## Returns
  - `%Foundation.Types.Error{}` with normalized error information
  """
  @spec normalize_jido_error(Jido.Error.t() | map(), keyword()) :: FoundationError.t()
  def normalize_jido_error(jido_error, opts \\ []) do
    preserve_context = Keyword.get(opts, :preserve_context, true)
    add_bridge_context = Keyword.get(opts, :add_bridge_context, true)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())

    # Map Jido error code to Foundation error code
    foundation_code = map_jido_error_code(get_jido_error_code(jido_error))
    
    # Extract error message
    message = get_jido_error_message(jido_error)
    
    # Build error context
    context = build_error_context(jido_error, preserve_context, add_bridge_context)
    
    # Create Foundation error
    foundation_error = FoundationError.new(
      foundation_code,
      message,
      context
    )
    
    # Add correlation tracking
    enhanced_error = %{foundation_error | 
      correlation_id: correlation_id,
      metadata: Map.merge(foundation_error.metadata || %{}, %{
        original_source: :jido,
        bridge_converted: true,
        converted_at: DateTime.utc_now()
      })
    }
    
    Logger.debug("Jido error normalized to Foundation format",
      jido_code: get_jido_error_code(jido_error),
      foundation_code: foundation_code,
      correlation_id: correlation_id
    )
    
    emit_error_conversion_telemetry(:jido_to_foundation, jido_error, enhanced_error)
    enhanced_error
  end

  @doc """
  Handles a Foundation error in Jido context, converting to Jido result format.
  
  ## Parameters
  - `foundation_error`: The Foundation error to handle
  - `opts`: Handling options
  
  ## Returns
  - `{:error, jido_error}` with converted error
  - `{:error, unified_error}` if conversion not possible
  """
  @spec handle_foundation_error_in_jido(FoundationError.t(), keyword()) :: 
        {:error, Jido.Error.t()} | {:error, unified_error()}
  def handle_foundation_error_in_jido(foundation_error, opts \\ []) do
    preserve_context = Keyword.get(opts, :preserve_context, true)
    create_unified = Keyword.get(opts, :create_unified, false)

    if create_unified do
      unified_error = create_unified_error_from_foundation(foundation_error, preserve_context)
      {:error, unified_error}
    else
      jido_error = convert_foundation_to_jido_error(foundation_error, preserve_context)
      
      Logger.debug("Foundation error converted to Jido format",
        foundation_code: foundation_error.code,
        jido_code: jido_error.code,
        correlation_id: foundation_error.correlation_id
      )
      
      emit_error_conversion_telemetry(:foundation_to_jido, foundation_error, jido_error)
      {:error, jido_error}
    end
  end

  @doc """
  Creates a unified error that can be used across both frameworks.
  
  ## Parameters
  - `code`: Error code
  - `message`: Error message
  - `context`: Error context
  - `opts`: Creation options
  
  ## Returns
  - `{:error, unified_error}` with standardized error information
  """
  @spec create_unified_error(error_code(), error_message(), error_context(), keyword()) ::
        {:error, unified_error()}
  def create_unified_error(code, message, context \\ %{}, opts \\ []) do
    source = Keyword.get(opts, :source, :bridge)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())
    recovery_suggestions = Keyword.get(opts, :recovery_suggestions, [])

    unified_error = %{
      code: code,
      message: message,
      source: source,
      context: context,
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      stack_trace: get_current_stacktrace(),
      recovery_suggestions: recovery_suggestions
    }

    Logger.warning("Unified error created",
      code: code,
      message: message,
      source: source,
      correlation_id: correlation_id
    )

    emit_unified_error_telemetry(unified_error)
    {:error, unified_error}
  end

  @doc """
  Wraps an operation with unified error handling across frameworks.
  
  ## Parameters
  - `operation`: The operation function to execute
  - `opts`: Error handling options
  
  ## Returns
  - `{:ok, result}` if operation succeeds
  - `{:error, unified_error}` if operation fails with unified error handling
  """
  @spec with_unified_error_handling(function(), keyword()) :: bridge_result()
  def with_unified_error_handling(operation, opts \\ []) do
    operation_context = Keyword.get(opts, :context, %{})
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())
    
    try do
      case operation.() do
        {:ok, result} -> {:ok, result}
        {:error, error} -> handle_operation_error(error, operation_context, correlation_id)
        result -> {:ok, result}
      end
    rescue
      error ->
        unified_error = create_unified_error_from_exception(error, operation_context, correlation_id)
        {:error, unified_error}
    catch
      :throw, value ->
        unified_error = create_unified_error_from_throw(value, operation_context, correlation_id)
        {:error, unified_error}
      
      :exit, reason ->
        unified_error = create_unified_error_from_exit(reason, operation_context, correlation_id)
        {:error, unified_error}
    end
  end

  @doc """
  Gets error statistics across both frameworks.
  
  ## Parameters
  - `time_window`: Time window for statistics in seconds (default: 300)
  
  ## Returns
  - `{:ok, stats}` with error statistics
  - `{:error, reason}` if statistics collection failed
  """
  @spec get_error_statistics(pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_error_statistics(time_window \\ 300) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -time_window, :second)

    stats = %{
      time_window: time_window,
      total_errors: count_total_errors(start_time, end_time),
      errors_by_source: count_errors_by_source(start_time, end_time),
      errors_by_code: count_errors_by_code(start_time, end_time),
      conversion_stats: get_conversion_statistics(start_time, end_time),
      recovery_stats: get_recovery_statistics(start_time, end_time),
      top_error_contexts: get_top_error_contexts(start_time, end_time)
    }

    {:ok, stats}
  end

  @doc """
  Configures error mappings between frameworks.
  
  ## Parameters
  - `mapping`: Error mapping configuration
  
  ## Returns
  - `:ok` if configuration successful
  - `{:error, reason}` if configuration failed
  """
  @spec configure_error_mappings(error_mapping()) :: bridge_result()
  def configure_error_mappings(mapping) do
    with :ok <- validate_error_mapping(mapping),
         :ok <- store_error_mapping(mapping) do
      Logger.info("Error mappings configured", 
        jido_to_foundation: map_size(mapping.jido_to_foundation),
        foundation_to_jido: map_size(mapping.foundation_to_jido)
      )
      :ok
    end
  end

  @doc """
  Gets current error mapping configuration.
  
  ## Returns
  - `{:ok, mapping}` with current error mapping
  - `{:error, reason}` if retrieval failed
  """
  @spec get_error_mappings() :: {:ok, error_mapping()} | {:error, term()}
  def get_error_mappings do
    case retrieve_error_mapping() do
      {:ok, mapping} -> {:ok, mapping}
      :error -> {:ok, default_error_mapping()}
    end
  end

  # Private implementation functions

  defp get_jido_error_code(%{code: code}), do: code
  defp get_jido_error_code(%{"code" => code}), do: String.to_atom(code)
  defp get_jido_error_code(_), do: :unknown_error

  defp get_jido_error_message(%{message: message}), do: message
  defp get_jido_error_message(%{"message" => message}), do: message
  defp get_jido_error_message(_), do: "Unknown error"

  defp map_jido_error_code(jido_code) do
    mapping = get_current_jido_to_foundation_mapping()
    Map.get(mapping, jido_code, :external_service_error)
  end

  defp build_error_context(jido_error, preserve_context, add_bridge_context) do
    base_context = if preserve_context do
      extract_jido_error_context(jido_error)
    else
      %{}
    end

    if add_bridge_context do
      Map.merge(base_context, %{
        bridge_info: %{
          converted_from: :jido,
          bridge_version: "1.0",
          converted_at: DateTime.utc_now()
        }
      })
    else
      base_context
    end
  end

  defp extract_jido_error_context(%{context: context}) when is_map(context), do: context
  defp extract_jido_error_context(%{"context" => context}) when is_map(context), do: context
  defp extract_jido_error_context(_), do: %{}

  defp convert_foundation_to_jido_error(foundation_error, preserve_context) do
    jido_code = map_foundation_error_code(foundation_error.code)
    
    context = if preserve_context do
      Map.merge(foundation_error.context || %{}, %{
        foundation_code: foundation_error.code,
        correlation_id: foundation_error.correlation_id
      })
    else
      %{}
    end

    # Create Jido error (assuming Jido.Error structure)
    %{
      code: jido_code,
      message: foundation_error.message,
      context: context,
      timestamp: DateTime.utc_now()
    }
  end

  defp map_foundation_error_code(foundation_code) do
    mapping = get_current_foundation_to_jido_mapping()
    Map.get(mapping, foundation_code, :external_error)
  end

  defp create_unified_error_from_foundation(foundation_error, preserve_context) do
    context = if preserve_context do
      Map.merge(foundation_error.context || %{}, %{
        original_error: foundation_error,
        converted_from: :foundation
      })
    else
      %{converted_from: :foundation}
    end

    %{
      code: foundation_error.code,
      message: foundation_error.message,
      source: :foundation,
      context: context,
      correlation_id: foundation_error.correlation_id || generate_correlation_id(),
      timestamp: DateTime.utc_now(),
      stack_trace: foundation_error.stacktrace || [],
      recovery_suggestions: extract_recovery_suggestions(foundation_error)
    }
  end

  defp handle_operation_error(error, operation_context, correlation_id) do
    case detect_error_source(error) do
      :jido ->
        foundation_error = normalize_jido_error(error, correlation_id: correlation_id)
        {:error, foundation_error}
        
      :foundation ->
        handle_foundation_error_in_jido(error, correlation_id: correlation_id)
        
      :unknown ->
        create_unified_error(
          :unknown_operation_error,
          "Operation failed with unknown error format",
          Map.merge(operation_context, %{original_error: error}),
          correlation_id: correlation_id
        )
    end
  end

  defp create_unified_error_from_exception(exception, context, correlation_id) do
    %{
      code: :exception_raised,
      message: Exception.message(exception),
      source: :bridge,
      context: Map.merge(context, %{
        exception_type: exception.__struct__,
        exception: exception
      }),
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      stack_trace: get_current_stacktrace(),
      recovery_suggestions: ["Check input parameters", "Verify system state", "Retry operation"]
    }
  end

  defp create_unified_error_from_throw(value, context, correlation_id) do
    %{
      code: :throw_caught,
      message: "Operation threw value: #{inspect(value)}",
      source: :bridge,
      context: Map.merge(context, %{thrown_value: value}),
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      stack_trace: get_current_stacktrace(),
      recovery_suggestions: ["Check operation logic", "Verify throw conditions"]
    }
  end

  defp create_unified_error_from_exit(reason, context, correlation_id) do
    %{
      code: :process_exit,
      message: "Process exited with reason: #{inspect(reason)}",
      source: :bridge,
      context: Map.merge(context, %{exit_reason: reason}),
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      stack_trace: get_current_stacktrace(),
      recovery_suggestions: ["Check process health", "Verify system resources", "Restart operation"]
    }
  end

  defp detect_error_source(error) do
    cond do
      is_map(error) and Map.has_key?(error, :code) -> :jido
      is_struct(error, FoundationError) -> :foundation
      true -> :unknown
    end
  end

  defp emit_error_conversion_telemetry(conversion_type, source_error, target_error) do
    :telemetry.execute(
      [:jido_foundation, :error_bridge, :conversion],
      %{count: 1},
      %{
        conversion_type: conversion_type,
        source_code: get_error_code(source_error),
        target_code: get_error_code(target_error),
        converted_at: DateTime.utc_now()
      }
    )
  end

  defp emit_unified_error_telemetry(unified_error) do
    :telemetry.execute(
      [:jido_foundation, :error_bridge, :unified_error],
      %{count: 1},
      %{
        error_code: unified_error.code,
        error_source: unified_error.source,
        correlation_id: unified_error.correlation_id
      }
    )
  end

  defp get_error_code(%{code: code}), do: code
  defp get_error_code(%{"code" => code}), do: code
  defp get_error_code(_), do: :unknown

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp get_current_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} -> stacktrace
      _ -> []
    end
  end

  defp extract_recovery_suggestions(%{metadata: %{recovery_suggestions: suggestions}}) 
       when is_list(suggestions), do: suggestions
  defp extract_recovery_suggestions(_), do: []

  defp validate_error_mapping(mapping) do
    cond do
      not is_map(mapping) -> {:error, :invalid_mapping_format}
      not Map.has_key?(mapping, :jido_to_foundation) -> {:error, :missing_jido_to_foundation}
      not Map.has_key?(mapping, :foundation_to_jido) -> {:error, :missing_foundation_to_jido}
      true -> :ok
    end
  end

  # Configuration storage functions (placeholder implementations)

  defp store_error_mapping(_mapping), do: :ok
  defp retrieve_error_mapping, do: :error

  defp get_current_jido_to_foundation_mapping do
    %{
      validation_failed: :validation_error,
      network_error: :network_failure,
      timeout: :timeout_error,
      permission_denied: :authorization_error,
      not_found: :resource_not_found
    }
  end

  defp get_current_foundation_to_jido_mapping do
    %{
      validation_error: :validation_failed,
      network_failure: :network_error,
      timeout_error: :timeout,
      authorization_error: :permission_denied,
      resource_not_found: :not_found
    }
  end

  defp default_error_mapping do
    %{
      jido_to_foundation: get_current_jido_to_foundation_mapping(),
      foundation_to_jido: get_current_foundation_to_jido_mapping()
    }
  end

  # Statistics functions (placeholder implementations)

  defp count_total_errors(_start_time, _end_time), do: 0
  defp count_errors_by_source(_start_time, _end_time), do: %{}
  defp count_errors_by_code(_start_time, _end_time), do: %{}
  defp get_conversion_statistics(_start_time, _end_time), do: %{}
  defp get_recovery_statistics(_start_time, _end_time), do: %{}
  defp get_top_error_contexts(_start_time, _end_time), do: []
end
