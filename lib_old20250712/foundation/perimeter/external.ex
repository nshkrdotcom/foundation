defmodule Foundation.Perimeter.External do
  @moduledoc """
  External validation contracts for Foundation AI systems.
  Uses simple validation with real domain logic.
  """

  def create_dspex_program(params) do
    Foundation.Perimeter.validate_external(params, %{
      name: {:string, required: true, min: 1, max: 100},
      description: {:string, max: 1000},
      schema_fields: {:list, required: true, validate: &validate_schema_fields/1},
      optimization_config: {:map, validate: &validate_optimization_config/1},
      metadata: {:map, default: %{}}
    })
  end
  
  def deploy_jido_agent(params) do
    Foundation.Perimeter.validate_external(params, %{
      agent_spec: {:map, required: true, validate: &validate_jido_agent_spec/1},
      clustering_config: {:map, validate: &validate_clustering_config/1},
      placement_strategy: {:atom, values: [:load_balanced, :capability_matched, :leader_only], default: :load_balanced},
      resource_limits: {:map, validate: &validate_resource_limits/1},
      monitoring_config: {:map, validate: &validate_monitoring_config/1}
    })
  end
  
  def execute_ml_pipeline(params) do
    Foundation.Perimeter.validate_external(params, %{
      pipeline_id: {:string, required: true},
      input_data: {:map, required: true, validate: &validate_ml_input_data/1},
      execution_options: {:map, validate: &validate_execution_options/1},
      timeout_ms: {:integer, min: 1000, max: 600_000, default: 30_000},
      priority: {:atom, values: [:low, :normal, :high, :critical], default: :normal}
    })
  end
  
  def coordinate_agents(params) do
    Foundation.Perimeter.validate_external(params, %{
      agent_group: {:list, required: true, validate: &validate_agent_group/1},
      coordination_pattern: {:atom, required: true, values: [:consensus, :pipeline, :map_reduce, :auction, :hierarchical]},
      coordination_config: {:map, validate: &validate_coordination_config/1},
      timeout_ms: {:integer, min: 5000, max: 300_000, default: 60_000},
      economic_params: {:map, validate: &validate_economic_params/1}
    })
  end
  
  def optimize_variables(params) do
    Foundation.Perimeter.validate_external(params, %{
      program_module: {:atom, required: true, validate: &validate_dspex_program_module/1},
      training_data: {:list, required: true, validate: &validate_training_data/1},
      optimization_strategy: {:atom, values: [:simba, :mipro, :genetic, :multi_agent, :bayesian], default: :simba},
      performance_targets: {:map, validate: &validate_performance_targets/1},
      agent_coordination: {:map, validate: &validate_agent_coordination_config/1}
    })
  end

  # Validation helper functions - these are the valuable domain-specific contracts

  defp validate_schema_fields(fields) when is_list(fields) do
    with :ok <- ensure_all_maps(fields),
         :ok <- validate_field_specifications(fields) do
      :ok
    else
      error -> error
    end
  end
  defp validate_schema_fields(_), do: {:error, "schema_fields must be a list"}

  defp validate_optimization_config(%{strategy: strategy} = config) 
    when strategy in [:simba, :mipro, :genetic, :bayesian] do
    case strategy do
      :simba -> validate_simba_config(config)
      :mipro -> validate_mipro_config(config) 
      :genetic -> validate_genetic_config(config)
      :bayesian -> validate_bayesian_config(config)
    end
  end
  defp validate_optimization_config(nil), do: :ok  # nil is allowed for optional field
  defp validate_optimization_config(%{}), do: :ok  # Empty config is valid
  defp validate_optimization_config(_), do: {:error, "optimization_config must be a map"}

  defp validate_jido_agent_spec(%{type: type} = spec) 
    when type in [:task_agent, :coordinator_agent, :monitor_agent, :foundation_agent] do
    with :ok <- validate_agent_capabilities(Map.get(spec, :capabilities, [])),
         :ok <- validate_agent_initial_state(Map.get(spec, :initial_state, %{})) do
      :ok
    else
      error -> error
    end
  end
  defp validate_jido_agent_spec(_), do: {:error, "Invalid agent spec - missing or invalid type"}

  defp validate_clustering_config(%{enabled: enabled} = config) when is_boolean(enabled) do
    if enabled do
      with :ok <- validate_required_field(config, :nodes, :integer),
           :ok <- validate_required_field(config, :strategy, :atom) do
        validate_clustering_strategy(config.strategy)
      end
    else
      :ok
    end
  end
  defp validate_clustering_config(nil), do: :ok  # nil is allowed for optional field
  defp validate_clustering_config(%{}), do: :ok  # Empty config defaults to disabled
  defp validate_clustering_config(_), do: {:error, "clustering_config must be a map"}

  defp validate_resource_limits(%{} = limits) do
    allowed_keys = [:memory_mb, :cpu_cores, :disk_mb, :network_mbps]
    
    case Enum.all?(Map.keys(limits), &(&1 in allowed_keys)) do
      true -> validate_resource_values(limits)
      false -> {:error, "Invalid resource limit keys"}
    end
  end
  defp validate_resource_limits(nil), do: :ok  # nil is allowed for optional field
  defp validate_resource_limits(_), do: {:error, "resource_limits must be a map"}

  defp validate_monitoring_config(%{} = _config) do
    # Basic monitoring config validation
    :ok
  end
  defp validate_monitoring_config(nil), do: :ok  # nil is allowed for optional field
  defp validate_monitoring_config(_), do: {:error, "monitoring_config must be a map"}

  defp validate_ml_input_data(data) when is_map(data), do: :ok
  defp validate_ml_input_data(_), do: {:error, "input_data must be a map"}

  defp validate_execution_options(nil), do: :ok  # nil is allowed for optional field
  defp validate_execution_options(%{} = _options), do: :ok
  defp validate_execution_options(_), do: {:error, "execution_options must be a map"}

  defp validate_agent_group(group) when is_list(group) and length(group) > 0, do: :ok
  defp validate_agent_group(_), do: {:error, "agent_group must be a non-empty list"}

  defp validate_coordination_config(nil), do: :ok  # nil is allowed for optional field
  defp validate_coordination_config(%{} = _config), do: :ok
  defp validate_coordination_config(_), do: {:error, "coordination_config must be a map"}

  defp validate_economic_params(nil), do: :ok  # nil is allowed for optional field
  defp validate_economic_params(%{} = _params), do: :ok
  defp validate_economic_params(_), do: {:error, "economic_params must be a map"}

  defp validate_dspex_program_module(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} -> :ok
      {:error, _} -> {:error, "Program module not found"}
    end
  end
  defp validate_dspex_program_module(_), do: {:error, "program_module must be an atom"}

  defp validate_training_data(data) when is_list(data) and length(data) > 0, do: :ok
  defp validate_training_data(_), do: {:error, "training_data must be a non-empty list"}

  defp validate_performance_targets(nil), do: :ok  # nil is allowed for optional field
  defp validate_performance_targets(%{} = _targets), do: :ok
  defp validate_performance_targets(_), do: {:error, "performance_targets must be a map"}

  defp validate_agent_coordination_config(nil), do: :ok  # nil is allowed for optional field
  defp validate_agent_coordination_config(%{} = _config), do: :ok
  defp validate_agent_coordination_config(_), do: {:error, "agent_coordination must be a map"}

  # Helper validation functions

  defp ensure_all_maps(fields) do
    case Enum.all?(fields, &is_map/1) do
      true -> :ok
      false -> {:error, "All schema fields must be maps"}
    end
  end

  defp validate_field_specifications(fields) do
    required_keys = [:name, :type]
    
    Enum.reduce_while(fields, :ok, fn field, _acc ->
      case Enum.all?(required_keys, &Map.has_key?(field, &1)) do
        true -> {:cont, :ok}
        false -> {:halt, {:error, "Schema field missing required keys: #{inspect(required_keys)}"}}
      end
    end)
  end

  defp validate_simba_config(%{} = _config), do: :ok
  defp validate_mipro_config(%{} = _config), do: :ok
  defp validate_genetic_config(%{} = _config), do: :ok
  defp validate_bayesian_config(%{} = _config), do: :ok

  defp validate_agent_capabilities(capabilities) when is_list(capabilities), do: :ok
  defp validate_agent_capabilities(_), do: {:error, "Agent capabilities must be a list"}

  defp validate_agent_initial_state(state) when is_map(state), do: :ok
  defp validate_agent_initial_state(_), do: {:error, "Agent initial state must be a map"}

  defp validate_required_field(map, key, type) do
    case Map.get(map, key) do
      value when type == :integer and is_integer(value) -> :ok
      value when type == :atom and is_atom(value) -> :ok
      value when type == :string and is_binary(value) -> :ok
      nil -> {:error, "Required field #{key} is missing"}
      _ -> {:error, "Field #{key} must be a #{type}"}
    end
  end

  defp validate_clustering_strategy(strategy) when strategy in [:capability_matched, :load_balanced, :geographic], do: :ok
  defp validate_clustering_strategy(_), do: {:error, "Invalid clustering strategy"}

  defp validate_resource_values(limits) do
    Enum.reduce_while(limits, :ok, fn
      {_key, value}, _acc when is_integer(value) and value > 0 -> {:cont, :ok}
      {key, _value}, _acc -> {:halt, {:error, "Resource limit #{key} must be a positive integer"}}
    end)
  end
end