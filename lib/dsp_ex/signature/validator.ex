defmodule DSPEx.Signature.Validator do
  @moduledoc """
  Validation functions for DSPy signature inputs and outputs.
  """

  alias DSPEx.Signature.Types

  @doc """
  Validate input data against a compiled signature.
  """
  def validate_input(compiled_signature, input_data) when is_map(input_data) do
    compiled_signature.inputs
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
      case validate_field(field, input_data) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
        error -> {:halt, error}
      end
    end)
  end

  def validate_input(_signature, input_data) do
    {:error, "Input data must be a map, got: #{inspect(input_data)}"}
  end

  @doc """
  Validate output data against a compiled signature.
  """
  def validate_output(compiled_signature, output_data) when is_map(output_data) do
    compiled_signature.outputs
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
      case validate_field(field, output_data) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
        error -> {:halt, error}
      end
    end)
  end

  def validate_output(_signature, output_data) do
    {:error, "Output data must be a map, got: #{inspect(output_data)}"}
  end

  ## Private Functions

  defp validate_field(field, data) do
    case Map.fetch(data, field.name) do
      {:ok, value} ->
        validate_type(value, field.type, field.type_params)
        
      :error when field.optional ->
        {:ok, nil}
        
      :error ->
        {:error, "Required field '#{field.name}' is missing"}
    end
  end

  defp validate_type(nil, _type, _params), do: {:ok, nil}

  defp validate_type(value, :string, []) when is_binary(value), do: {:ok, value}
  defp validate_type(value, :integer, []) when is_integer(value), do: {:ok, value}
  defp validate_type(value, :float, []) when is_number(value), do: {:ok, value}
  defp validate_type(value, :boolean, []) when is_boolean(value), do: {:ok, value}
  defp validate_type(value, :map, []) when is_map(value), do: {:ok, value}

  defp validate_type(value, :list, [inner_type]) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case validate_type(item, inner_type.type, inner_type.params) do
        {:ok, validated_item} -> {:cont, {:ok, [validated_item | acc]}}
        {:error, reason} -> {:halt, {:error, "List item at index #{index}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp validate_type(value, expected_type, _params) do
    {:error, "Expected #{expected_type}, got: #{inspect(value)}"}
  end
end