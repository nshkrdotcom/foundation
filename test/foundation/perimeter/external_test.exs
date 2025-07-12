defmodule Foundation.Perimeter.ExternalTest do
  use ExUnit.Case
  
  describe "create_dspex_program/1" do
    test "validates valid DSPEx program creation" do
      valid_params = %{
        name: "Test Program",
        description: "Test description",
        schema_fields: [%{name: :input, type: :string, required: true}],
        optimization_config: %{strategy: :simba},
        metadata: %{version: "1.0"}
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.create_dspex_program(valid_params)
      assert validated.name == "Test Program"
      assert is_list(validated.schema_fields)
    end

    test "rejects invalid program name" do
      invalid_params = %{
        name: "", # Too short
        schema_fields: [%{name: :input, type: :string}]
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.create_dspex_program(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> field == :name and msg =~ "should be at least 1" end)
    end

    test "rejects invalid schema fields" do
      invalid_params = %{
        name: "Test Program",
        schema_fields: "not a list"
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.create_dspex_program(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> field == :schema_fields and msg =~ "must be a list" end)
    end
  end

  describe "deploy_jido_agent/1" do
    test "validates valid Jido agent deployment" do
      valid_params = %{
        agent_spec: %{type: :task_agent, capabilities: [:nlp]},
        placement_strategy: :load_balanced,
        resource_limits: %{memory_mb: 512},
        monitoring_config: %{}
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.deploy_jido_agent(valid_params)
      assert validated.placement_strategy == :load_balanced
      assert is_map(validated.agent_spec)
    end

    test "applies default placement strategy" do
      valid_params = %{
        agent_spec: %{type: :task_agent, capabilities: [:nlp]}
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.deploy_jido_agent(valid_params)
      assert validated.placement_strategy == :load_balanced
    end

    test "rejects invalid placement strategy" do
      invalid_params = %{
        agent_spec: %{type: :task_agent, capabilities: [:nlp]},
        placement_strategy: :invalid_strategy
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.deploy_jido_agent(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> 
        field == :placement_strategy and msg =~ "must be one of" 
      end)
    end
  end

  describe "execute_ml_pipeline/1" do
    test "validates valid ML pipeline execution" do
      valid_params = %{
        pipeline_id: "pipeline_123",
        input_data: %{features: [1, 2, 3]},
        timeout_ms: 30_000,
        priority: :high
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.execute_ml_pipeline(valid_params)
      assert validated.pipeline_id == "pipeline_123"
      assert validated.priority == :high
    end

    test "applies default timeout and priority" do
      valid_params = %{
        pipeline_id: "pipeline_123",
        input_data: %{features: [1, 2, 3]}
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.execute_ml_pipeline(valid_params)
      assert validated.timeout_ms == 30_000
      assert validated.priority == :normal
    end

    test "rejects timeout outside range" do
      invalid_params = %{
        pipeline_id: "pipeline_123",
        input_data: %{features: [1, 2, 3]},
        timeout_ms: 500 # Too low
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.execute_ml_pipeline(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> 
        field == :timeout_ms and msg =~ "should be at least 1000" 
      end)
    end
  end

  describe "coordinate_agents/1" do
    test "validates valid agent coordination" do
      valid_params = %{
        agent_group: ["agent1", "agent2", "agent3"],
        coordination_pattern: :consensus,
        coordination_config: %{threshold: 0.8},
        timeout_ms: 60_000
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.coordinate_agents(valid_params)
      assert validated.coordination_pattern == :consensus
      assert is_list(validated.agent_group)
    end

    test "rejects invalid coordination pattern" do
      invalid_params = %{
        agent_group: ["agent1", "agent2"],
        coordination_pattern: :invalid_pattern
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.coordinate_agents(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> 
        field == :coordination_pattern and msg =~ "must be one of" 
      end)
    end

    test "rejects empty agent group" do
      invalid_params = %{
        agent_group: [],
        coordination_pattern: :consensus
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.coordinate_agents(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> 
        field == :agent_group and msg =~ "must be a non-empty list" 
      end)
    end
  end

  describe "optimize_variables/1" do
    test "validates valid variable optimization" do
      valid_params = %{
        program_module: Foundation.Perimeter, # Use an existing module for test
        training_data: [%{input: "test", output: "result"}],
        optimization_strategy: :simba,
        performance_targets: %{accuracy: 0.9}
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.optimize_variables(valid_params)
      assert validated.program_module == Foundation.Perimeter
      assert validated.optimization_strategy == :simba
    end

    test "applies default optimization strategy" do
      valid_params = %{
        program_module: Foundation.Perimeter,
        training_data: [%{input: "test", output: "result"}]
      }
      
      assert {:ok, validated} = Foundation.Perimeter.External.optimize_variables(valid_params)
      assert validated.optimization_strategy == :simba
    end

    test "rejects non-existent program module" do
      invalid_params = %{
        program_module: NonExistentModule,
        training_data: [%{input: "test", output: "result"}]
      }
      
      assert {:error, errors} = Foundation.Perimeter.External.optimize_variables(invalid_params)
      assert Enum.any?(errors, fn {field, msg} -> 
        field == :program_module and msg =~ "Program module not found" 
      end)
    end
  end
end