defmodule DSPEx.Signature.DSLTest do
  use ExUnit.Case, async: true
  
  describe "DSPy signature compilation" do
    test "basic signature compiles correctly" do
      defmodule TestSignature do
        use DSPEx.Signature
        signature "input: str -> output: str"
      end
      
      sig = TestSignature.__signature__()
      assert sig != nil
      assert sig.raw_definition == "input: str -> output: str"
      assert length(sig.inputs) == 1
      assert length(sig.outputs) == 1
    end

    test "complex signature with optional fields" do
      defmodule ComplexSignature do
        use DSPEx.Signature
        signature "question: str, context?: str, temperature?: float -> answer: str, confidence: float"
      end
      
      sig = ComplexSignature.__signature__()
      assert length(sig.inputs) == 3
      assert length(sig.outputs) == 2
      assert sig.required_inputs == [:question]
      assert Enum.sort(sig.optional_inputs) == [:context, :temperature]
    end

    test "signature validation works" do
      defmodule ValidationTest do
        use DSPEx.Signature
        signature "name: str -> greeting: str"
      end
      
      sig = ValidationTest.__signature__()
      
      # Valid input
      {:ok, validated} = DSPEx.Signature.validate_input(sig, %{name: "Alice"})
      assert validated.name == "Alice"
      
      # Invalid input - missing required field
      {:error, _reason} = DSPEx.Signature.validate_input(sig, %{})
      
      # Invalid input - wrong type
      {:error, _reason} = DSPEx.Signature.validate_input(sig, %{name: 123})
    end
  end
end