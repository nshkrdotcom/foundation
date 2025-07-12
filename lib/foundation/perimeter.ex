defmodule Foundation.Perimeter do
  @moduledoc """
  Simple validation boundaries for Foundation AI systems.
  
  Three validation levels:
  - external: Strict validation for untrusted input
  - internal: Light validation for service boundaries
  - trusted: No validation for performance paths
  
  ## Examples
  
      # External API validation
      {:ok, user} = validate_external(params, %{
        name: {:string, required: true, min: 1, max: 100},
        email: {:string, required: true},
        age: {:integer, required: false}
      })
      
      # Internal service validation  
      {:ok, task} = validate_internal(data, %{
        id: :string,
        type: :atom,
        payload: :map
      })
      
      # Trusted high-performance path
      {:ok, signal} = validate_trusted(signal, :any)
  """

  @doc """
  Strict validation for external/untrusted input.
  
  Supports:
  - Required field validation
  - Type checking (string, integer, map, list)
  - Length constraints for strings
  - Custom validation functions
  """
  def validate_external(data, schema) when is_map(data) and is_map(schema) do
    case validate_external_fields(data, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, errors}
    end
  end

  def validate_external(data, _schema) do
    {:error, "External validation requires map input, got: #{inspect(data)}"}
  end

  @doc """
  Light validation for internal service boundaries.
  
  Performs basic type checking without strict constraints.
  More permissive than external validation for internal trust.
  """
  def validate_internal(data, schema) when is_map(data) and is_map(schema) do
    case validate_basic_types(data, schema) do
      :ok -> {:ok, data}
      {:error, errors} -> {:error, errors}
    end
  end

  def validate_internal(data, _schema) do
    # Internal validation is permissive - accept non-map data
    {:ok, data}
  end

  @doc """
  No validation for trusted/high-performance paths.
  
  Always returns {:ok, data} immediately for maximum performance.
  Use this for internal calls where data is already trusted.
  """
  def validate_trusted(data, _schema), do: {:ok, data}

  # Private helper functions

  defp validate_external_fields(data, schema) do
    # Apply defaults first
    data_with_defaults = apply_defaults(data, schema)
    
    # Validate each field
    case validate_all_fields(data_with_defaults, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, errors}
    end
  end

  defp apply_defaults(data, schema) do
    Enum.reduce(schema, data, fn
      {field, {:string, opts}}, acc ->
        case Map.get(acc, field) do
          nil -> 
            case Keyword.get(opts, :default) do
              nil -> acc
              default -> Map.put(acc, field, default)
            end
          _ -> acc
        end
      {field, {:integer, opts}}, acc ->
        case Map.get(acc, field) do
          nil -> 
            case Keyword.get(opts, :default) do
              nil -> acc
              default -> Map.put(acc, field, default)
            end
          _ -> acc
        end
      {field, {:map, opts}}, acc ->
        case Map.get(acc, field) do
          nil -> 
            case Keyword.get(opts, :default) do
              nil -> acc
              default -> Map.put(acc, field, default)
            end
          _ -> acc
        end
      {field, {:atom, opts}}, acc ->
        case Map.get(acc, field) do
          nil -> 
            case Keyword.get(opts, :default) do
              nil -> acc
              default -> Map.put(acc, field, default)
            end
          _ -> acc
        end
      _, acc -> acc
    end)
  end

  defp validate_all_fields(data, schema) do
    errors = Enum.reduce(schema, [], fn {field, field_schema}, acc ->
      case validate_field(data, field, field_schema) do
        :ok -> acc
        {:error, error} -> [{field, error} | acc]
      end
    end)

    case errors do
      [] -> {:ok, data}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_field(data, field, {:string, opts}) do
    value = Map.get(data, field)
    
    with :ok <- validate_required(field, value, opts),
         :ok <- validate_string_type(field, value),
         :ok <- validate_string_length(field, value, opts),
         :ok <- validate_custom(field, value, opts) do
      :ok
    end
  end

  defp validate_field(data, field, {:integer, opts}) do
    value = Map.get(data, field)
    
    with :ok <- validate_required(field, value, opts),
         :ok <- validate_integer_type(field, value),
         :ok <- validate_integer_range(field, value, opts),
         :ok <- validate_custom(field, value, opts) do
      :ok
    end
  end

  defp validate_field(data, field, {:map, opts}) do
    value = Map.get(data, field)
    
    with :ok <- validate_required(field, value, opts),
         :ok <- validate_map_type(field, value),
         :ok <- validate_custom(field, value, opts) do
      :ok
    end
  end

  defp validate_field(data, field, {:list, opts}) do
    value = Map.get(data, field)
    
    with :ok <- validate_required(field, value, opts),
         :ok <- validate_list_type(field, value),
         :ok <- validate_custom(field, value, opts) do
      :ok
    end
  end

  defp validate_field(data, field, {:atom, opts}) do
    value = Map.get(data, field)
    
    with :ok <- validate_required(field, value, opts),
         :ok <- validate_atom_type(field, value),
         :ok <- validate_atom_values(field, value, opts),
         :ok <- validate_custom(field, value, opts) do
      :ok
    end
  end

  defp validate_field(_data, _field, _schema), do: :ok

  defp validate_required(_field, value, opts) do
    required = Keyword.get(opts, :required, false)
    
    if required do
      case value do
        nil -> {:error, "is required"}
        "" -> {:error, "should be at least 1 character(s)"}
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp validate_string_type(_field, nil), do: :ok
  defp validate_string_type(_field, value) when is_binary(value), do: :ok
  defp validate_string_type(_field, _value), do: {:error, "must be a string"}

  defp validate_string_length(_field, nil, _opts), do: :ok
  defp validate_string_length(field, value, opts) when is_binary(value) do
    length = String.length(value)
    
    with :ok <- validate_min_length(field, length, opts),
         :ok <- validate_max_length(field, length, opts) do
      :ok
    end
  end
  defp validate_string_length(_field, _value, _opts), do: :ok

  defp validate_min_length(_field, length, opts) do
    case Keyword.get(opts, :min) do
      nil -> :ok
      min when length >= min -> :ok
      min -> {:error, "should be at least #{min} character(s)"}
    end
  end

  defp validate_max_length(_field, length, opts) do
    case Keyword.get(opts, :max) do
      nil -> :ok
      max when length <= max -> :ok
      max -> {:error, "should be at most #{max} character(s)"}
    end
  end

  defp validate_integer_type(_field, nil), do: :ok
  defp validate_integer_type(_field, value) when is_integer(value), do: :ok
  defp validate_integer_type(_field, _value), do: {:error, "must be an integer"}

  defp validate_integer_range(_field, nil, _opts), do: :ok
  defp validate_integer_range(field, value, opts) when is_integer(value) do
    with :ok <- validate_min_value(field, value, opts),
         :ok <- validate_max_value(field, value, opts) do
      :ok
    end
  end
  defp validate_integer_range(_field, _value, _opts), do: :ok

  defp validate_min_value(_field, value, opts) do
    case Keyword.get(opts, :min) do
      nil -> :ok
      min when value >= min -> :ok
      min -> {:error, "should be at least #{min}"}
    end
  end

  defp validate_max_value(_field, value, opts) do
    case Keyword.get(opts, :max) do
      nil -> :ok
      max when value <= max -> :ok
      max -> {:error, "should be at most #{max}"}
    end
  end

  defp validate_map_type(_field, nil), do: :ok
  defp validate_map_type(_field, value) when is_map(value), do: :ok
  defp validate_map_type(_field, _value), do: {:error, "must be a map"}

  defp validate_list_type(_field, nil), do: :ok
  defp validate_list_type(_field, value) when is_list(value), do: :ok
  defp validate_list_type(_field, _value), do: {:error, "must be a list"}

  defp validate_atom_type(_field, nil), do: :ok
  defp validate_atom_type(_field, value) when is_atom(value), do: :ok
  defp validate_atom_type(_field, _value), do: {:error, "must be an atom"}

  defp validate_atom_values(_field, nil, _opts), do: :ok
  defp validate_atom_values(_field, value, opts) when is_atom(value) do
    case Keyword.get(opts, :values) do
      nil -> :ok
      allowed when is_list(allowed) ->
        if value in allowed do
          :ok
        else
          {:error, "must be one of #{inspect(allowed)}"}
        end
      _ -> :ok
    end
  end
  defp validate_atom_values(_field, _value, _opts), do: :ok

  defp validate_custom(_field, value, opts) do
    case Keyword.get(opts, :validate) do
      nil -> :ok
      validate_fn when is_function(validate_fn, 1) ->
        case validate_fn.(value) do
          :ok -> :ok
          {:error, msg} -> {:error, msg}
          _ -> {:error, "custom validation failed"}
        end
      _ -> :ok
    end
  end

  defp validate_basic_types(data, schema) do
    errors = Enum.reduce(schema, [], fn
      {key, :string}, acc ->
        case Map.get(data, key) do
          val when is_binary(val) or is_nil(val) -> acc
          _other -> [{key, "expected string"} | acc]
        end

      {key, :integer}, acc ->
        case Map.get(data, key) do
          val when is_integer(val) or is_nil(val) -> acc
          _other -> [{key, "expected integer"} | acc]
        end

      {key, :map}, acc ->
        case Map.get(data, key) do
          val when is_map(val) or is_nil(val) -> acc
          _other -> [{key, "expected map"} | acc]
        end

      {key, :atom}, acc ->
        case Map.get(data, key) do
          val when is_atom(val) or is_nil(val) -> acc
          _other -> [{key, "expected atom"} | acc]
        end

      {key, :list}, acc ->
        case Map.get(data, key) do
          val when is_list(val) or is_nil(val) -> acc
          _other -> [{key, "expected list"} | acc]
        end

      _other, acc -> acc
    end)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

end