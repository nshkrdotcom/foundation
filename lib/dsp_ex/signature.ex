defmodule DSPEx.Signature do
  @moduledoc """
  Native DSPy signature syntax support for ElixirML.

  This module provides the revolutionary native DSPy signature syntax that allows
  Elixir developers to define ML signatures using Python-like syntax:

      signature "question: str, context?: str -> answer: str, confidence: float"

  The signatures are compiled at build time for maximum performance while maintaining
  full compatibility with DSPy patterns and conventions.

  ## Features

  - Native Python-like signature syntax
  - Compile-time validation and optimization
  - Runtime type checking and validation
  - Automatic variable extraction for optimization
  - JSON schema generation for API integration
  - Full DSPy compatibility

  ## Usage

      defmodule MyQA do
        use DSPEx.Signature

        signature "question: str, context?: str -> answer: str, confidence: float"
      end

      # Compiled signature is available at runtime
      MyQA.__signature__()
      # => %DSPEx.Signature.CompiledSignature{...}
  """

  alias DSPEx.Signature.{DSL, Compiler, Types}

  @type compiled_signature :: %{
    inputs: [Types.field()],
    outputs: [Types.field()],
    raw_definition: String.t(),
    compiled_at: DateTime.t(),
    module: module()
  }

  defmacro __using__(opts \\ []) do
    quote do
      import DSPEx.Signature.DSL
      Module.register_attribute(__MODULE__, :dspex_signatures, accumulate: true)
      
      @before_compile DSPEx.Signature
    end
  end

  defmacro __before_compile__(env) do
    signatures = Module.get_attribute(env.module, :dspex_signatures, [])
    
    case signatures do
      [] ->
        quote do
          def __signature__(), do: nil
        end
        
      [signature_def | _] ->
        # Compile the signature at build time
        compiled = Compiler.compile(signature_def, env.module)
        
        quote do
          def __signature__() do
            unquote(Macro.escape(compiled))
          end
        end
    end
  end

  @doc """
  Get a compiled signature for a module.
  """
  def get_signature(module) when is_atom(module) do
    if function_exported?(module, :__signature__, 0) do
      module.__signature__()
    else
      nil
    end
  end

  @doc """
  Validate input data against a compiled signature.
  """
  def validate_input(compiled_signature, input_data) do
    DSPEx.Signature.Validator.validate_input(compiled_signature, input_data)
  end

  @doc """
  Validate output data against a compiled signature.
  """
  def validate_output(compiled_signature, output_data) do
    DSPEx.Signature.Validator.validate_output(compiled_signature, output_data)
  end

  @doc """
  Generate a JSON schema from a compiled signature.
  """
  def to_json_schema(compiled_signature) do
    DSPEx.Signature.JSONSchema.generate(compiled_signature)
  end
end