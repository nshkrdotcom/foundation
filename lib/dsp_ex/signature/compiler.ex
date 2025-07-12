defmodule DSPEx.Signature.Compiler do
  @moduledoc """
  Compiler for DSPy signature definitions.

  Parses signature strings and compiles them into optimized runtime structures
  with full validation and type information.
  """

  alias DSPEx.Signature.{Types, Parser}

  @doc """
  Compile a signature definition string into an optimized runtime structure.
  """
  def compile(definition, module) when is_binary(definition) do
    case Parser.parse(definition) do
      {:ok, {inputs, outputs}} ->
        %{
          inputs: inputs,
          outputs: outputs,
          raw_definition: definition,
          compiled_at: DateTime.utc_now(),
          module: module,
          input_fields: Enum.map(inputs, & &1.name),
          output_fields: Enum.map(outputs, & &1.name),
          required_inputs: Enum.filter(inputs, &(!&1.optional)) |> Enum.map(& &1.name),
          optional_inputs: Enum.filter(inputs, & &1.optional) |> Enum.map(& &1.name)
        }
        
      {:error, reason} ->
        raise CompileError, 
          description: "Failed to compile signature '#{definition}': #{reason}",
          file: "signature definition"
    end
  end
end