defmodule DSPEx.Signature.Parser do
  @moduledoc """
  Parser for DSPy signature definition strings.

  Parses signature strings like:
    "question: str, context?: str -> answer: str, confidence: float"

  Into structured field definitions with type information.
  """

  alias DSPEx.Signature.Types

  @doc """
  Parse a signature definition string.

  Returns `{:ok, {inputs, outputs}}` or `{:error, reason}`.
  """
  def parse(definition) when is_binary(definition) do
    definition
    |> String.trim()
    |> split_inputs_outputs()
    |> case do
      {:ok, {input_str, output_str}} ->
        with {:ok, inputs} <- parse_fields(input_str, :input),
             {:ok, outputs} <- parse_fields(output_str, :output) do
          {:ok, {inputs, outputs}}
        end
        
      error -> error
    end
  end

  defp split_inputs_outputs(definition) do
    case String.split(definition, "->", parts: 2) do
      [input_part, output_part] ->
        {:ok, {String.trim(input_part), String.trim(output_part)}}
        
      [_] ->
        {:error, "Signature must contain '->' separator between inputs and outputs"}
        
      _ ->
        {:error, "Signature contains multiple '->' separators"}
    end
  end

  defp parse_fields("", _direction), do: {:ok, []}
  
  defp parse_fields(fields_str, direction) do
    fields_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {field_str, index}, {:ok, acc} ->
      case parse_field(field_str, direction, index) do
        {:ok, field} -> {:cont, {:ok, [field | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      error -> error
    end
  end

  defp parse_field(field_str, direction, index) do
    # Parse "name?: type" or "name: type"
    case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_]*?)(\?)?:\s*(.+)$/, field_str) do
      [_, name, optional_marker, type_str] ->
        optional = optional_marker == "?"
        
        case parse_type(type_str) do
          {:ok, type_info} ->
            field = %Types.Field{
              name: String.to_atom(name),
              type: type_info.type,
              type_params: type_info.params,
              optional: optional,
              direction: direction,
              position: index,
              raw_definition: field_str
            }
            {:ok, field}
            
          error -> error
        end
        
      nil ->
        {:error, "Invalid field syntax: '#{field_str}'. Expected format: 'name: type' or 'name?: type'"}
    end
  end

  defp parse_type(type_str) do
    type_str = String.trim(type_str)
    
    case type_str do
      "str" -> {:ok, %{type: :string, params: []}}
      "int" -> {:ok, %{type: :integer, params: []}}
      "float" -> {:ok, %{type: :float, params: []}}
      "bool" -> {:ok, %{type: :boolean, params: []}}
      "dict" -> {:ok, %{type: :map, params: []}}
      
      # List types like "list[str]"
      list_type when is_binary(list_type) ->
        case Regex.run(~r/^list\[(.+)\]$/, list_type) do
          [_, inner_type] ->
            case parse_type(inner_type) do
              {:ok, inner_info} -> {:ok, %{type: :list, params: [inner_info]}}
              error -> error
            end
          nil ->
            {:error, "Unknown type: '#{type_str}'"}
        end
    end
  end
end