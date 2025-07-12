defmodule DSPEx.Signature.DSL do
  @moduledoc """
  DSL for defining native DSPy signatures in Elixir.

  Provides the `signature/1` macro that parses DSPy-style signature definitions
  and compiles them into optimized Elixir structures.

  ## Syntax

  The signature syntax follows DSPy conventions:

      signature "input1: type1, input2?: type2 -> output1: type3, output2: type4"

  ### Supported Types

  - `str` - String values
  - `int` - Integer values  
  - `float` - Floating point values
  - `bool` - Boolean values
  - `list[T]` - Lists of type T
  - `dict` - Map/dictionary values

  ### Optional Fields

  Fields marked with `?` are optional:

      signature "question: str, context?: str -> answer: str"

  ### Multiple Inputs/Outputs

  Multiple fields are comma-separated:

      signature "q1: str, q2: str -> a1: str, a2: str, confidence: float"
  """

  @doc """
  Define a DSPy signature for the current module.

  ## Examples

      signature "question: str -> answer: str"
      signature "question: str, context?: str -> answer: str, confidence: float"
  """
  defmacro signature(definition) when is_binary(definition) do
    quote do
      @dspex_signatures unquote(definition)
    end
  end

  defmacro signature(definition) do
    raise ArgumentError, """
    signature/1 expects a string definition, got: #{inspect(definition)}

    Usage:
      signature "question: str -> answer: str"
    """
  end
end