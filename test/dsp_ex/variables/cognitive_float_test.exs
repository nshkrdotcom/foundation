defmodule DSPEx.Variables.CognitiveFloatTest do
  use ExUnit.Case, async: false

  setup do
    # Start necessary registries
    {:ok, _} = Registry.start_link(keys: :unique, name: DSPEx.Variables.Registry)
    {:ok, _} = DSPEx.Foundation.Bridge.start_link([])
    :ok
  end

  describe "cognitive variable as Jido agent" do
    test "cognitive variable starts and registers correctly" do
      {:ok, pid} = DSPEx.Variables.CognitiveFloat.start_link(%{
        id: "test_var",
        name: :test_temperature,
        initial_value: 0.5,
        valid_range: {0.0, 1.0}
      })

      assert is_pid(pid)

      # Should be registered in variables registry
      case Registry.lookup(DSPEx.Variables.Registry, :test_temperature) do
        [{^pid, metadata}] ->
          assert metadata.type == :cognitive_float
          assert metadata.current_value == 0.5
        [] ->
          flunk("Variable not registered in registry")
      end
    end

    test "variable value can be retrieved and updated" do
      {:ok, _pid} = DSPEx.Variables.CognitiveFloat.start_link(%{
        id: "test_var2",
        name: :test_var2,
        initial_value: 0.3,
        valid_range: {0.0, 1.0}
      })

      # Get initial value
      {:ok, value} = DSPEx.Variables.CognitiveFloat.get_value(:test_var2)
      assert value == 0.3

      # Update value
      {:ok, _result} = DSPEx.Variables.CognitiveFloat.set_value(:test_var2, 0.7)

      # Verify update
      {:ok, new_value} = DSPEx.Variables.CognitiveFloat.get_value(:test_var2)
      assert new_value == 0.7
    end

    test "variable validation works correctly" do
      {:ok, _pid} = DSPEx.Variables.CognitiveFloat.start_link(%{
        id: "test_var3",
        name: :test_var3,
        initial_value: 0.5,
        valid_range: {0.0, 1.0}
      })

      # Valid update should succeed
      {:ok, _} = DSPEx.Variables.CognitiveFloat.set_value(:test_var3, 0.8)

      # Invalid update should fail (below minimum)
      case DSPEx.Variables.CognitiveFloat.set_value(:test_var3, -0.1) do
        {:error, _reason} -> :ok
        {:ok, _} -> flunk("Should reject value below minimum")
      end

      # Invalid update should fail (above maximum)
      case DSPEx.Variables.CognitiveFloat.set_value(:test_var3, 1.5) do
        {:error, _reason} -> :ok
        {:ok, _} -> flunk("Should reject value above maximum")
      end
    end

    test "variable statistics are tracked" do
      {:ok, pid} = DSPEx.Variables.CognitiveFloat.start_link(%{
        id: "test_var4",
        name: :test_var4,
        initial_value: 0.5,
        valid_range: {0.0, 1.0}
      })

      # Update value a few times
      {:ok, _} = DSPEx.Variables.CognitiveFloat.set_value(:test_var4, 0.6)
      {:ok, _} = DSPEx.Variables.CognitiveFloat.set_value(:test_var4, 0.7)

      # Get statistics
      {:ok, stats} = DSPEx.Variables.CognitiveFloat.get_stats(:test_var4)

      assert stats.name == :test_var4
      assert stats.current_value == 0.7
      assert stats.update_count >= 2
      assert stats.coordination_enabled == true
      assert is_map(stats.coordination_stats)
    end
  end

  describe "validation functions" do
    test "validate_value works correctly" do
      range = {0.0, 1.0}

      assert {:ok, 0.5} = DSPEx.Variables.CognitiveFloat.validate_value(0.5, range)
      assert {:ok, 0.0} = DSPEx.Variables.CognitiveFloat.validate_value(0.0, range)
      assert {:ok, 1.0} = DSPEx.Variables.CognitiveFloat.validate_value(1.0, range)

      assert {:error, :below_minimum, 0.0} = DSPEx.Variables.CognitiveFloat.validate_value(-0.1, range)
      assert {:error, :above_maximum, 1.0} = DSPEx.Variables.CognitiveFloat.validate_value(1.1, range)
      assert {:error, :invalid_value} = DSPEx.Variables.CognitiveFloat.validate_value("invalid", range)
    end

    test "coordination impact calculation" do
      assert :low_impact = DSPEx.Variables.CognitiveFloat.calculate_coordination_impact(0.5, 0.51, [])
      assert :medium_impact = DSPEx.Variables.CognitiveFloat.calculate_coordination_impact(0.5, 0.6, [:agent1, :agent2])
      assert :high_impact = DSPEx.Variables.CognitiveFloat.calculate_coordination_impact(0.2, 0.8, [:agent1, :agent2, :agent3])
    end

    test "consensus decision logic" do
      assert true = DSPEx.Variables.CognitiveFloat.should_use_consensus?(:cluster, :high_impact)
      assert true = DSPEx.Variables.CognitiveFloat.should_use_consensus?(:cluster, :medium_impact)
      assert false = DSPEx.Variables.CognitiveFloat.should_use_consensus?(:local, :low_impact)
      assert true = DSPEx.Variables.CognitiveFloat.should_use_consensus?(:global, :low_impact)
    end
  end
end