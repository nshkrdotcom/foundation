defmodule Foundation.TestHelpers.AgentFixtures do
  @moduledoc """
  Standardized agent configurations and test fixtures for the unified registry.

  This module provides pre-defined agent configurations that are commonly used
  in testing scenarios. It includes realistic agent setups for different types
  of ML and computation workloads.

  ## Agent Types

  - **Basic Workers**: Simple computation agents
  - **ML Agents**: Machine learning specific agents
  - **Coordination Agents**: Agents that manage other agents
  - **Specialist Agents**: Domain-specific agents (e.g., NLP, computer vision)

  ## Usage

      defmodule MyAgentTest do
        use ExUnit.Case
        import Foundation.TestHelpers.AgentFixtures

        test "ml agent capabilities" do
          config = ml_agent_config(:test_ml_agent, gpu: true)
          # ... test with config
        end
      end
  """

  @type agent_config :: %{
          id: atom(),
          type: atom(),
          module: module(),
          args: list(),
          capabilities: [atom()],
          restart_policy: atom(),
          metadata: map()
        }

  # ============================================================================
  # Basic Agent Configurations
  # ============================================================================

  @doc """
  Create a basic worker agent configuration.

  Basic workers are simple computation agents that can handle general tasks
  without specialized requirements.

  ## Parameters
  - `id` - Agent identifier (default: :test_worker)
  - `opts` - Additional options

  ## Options
  - `:capabilities` - List of capabilities (default: [:compute])
  - `:priority` - Agent priority (default: :normal)
  - `:max_tasks` - Maximum concurrent tasks (default: 1)

  ## Examples

      config = basic_worker_config()
      config = basic_worker_config(:worker1, capabilities: [:compute, :io])
  """
  @spec basic_worker_config(atom(), keyword()) :: agent_config()
  def basic_worker_config(id \\ :test_worker, opts \\ []) do
    capabilities = Keyword.get(opts, :capabilities, [:compute])
    priority = Keyword.get(opts, :priority, :normal)
    max_tasks = Keyword.get(opts, :max_tasks, 1)

    %{
      id: id,
      type: :worker,
      module: Foundation.TestHelpers.TestWorker,
      args: [],
      capabilities: capabilities,
      restart_policy: :temporary,
      metadata: %{
        priority: priority,
        max_concurrent_tasks: max_tasks,
        worker_type: :basic,
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Create an ML agent configuration.

  ML agents are specialized for machine learning workloads and include
  capabilities for model training, inference, and data processing.

  ## Parameters
  - `id` - Agent identifier (default: :ml_test_agent)
  - `opts` - ML-specific options

  ## Options
  - `:model_type` - Type of ML model (default: :general)
  - `:gpu` - GPU acceleration support (default: false)
  - `:memory_gb` - Memory requirement in GB (default: 4)
  - `:frameworks` - Supported ML frameworks (default: [:pytorch, :tensorflow])

  ## Examples

      config = ml_agent_config()
      config = ml_agent_config(:nlp_agent,
        model_type: :transformer,
        gpu: true,
        frameworks: [:huggingface]
      )
  """
  @spec ml_agent_config(atom(), keyword()) :: agent_config()
  def ml_agent_config(id \\ :ml_test_agent, opts \\ []) do
    model_type = Keyword.get(opts, :model_type, :general)
    gpu = Keyword.get(opts, :gpu, false)
    memory_gb = Keyword.get(opts, :memory_gb, 4)
    frameworks = Keyword.get(opts, :frameworks, [:pytorch, :tensorflow])

    base_capabilities = [:compute, :ml]
    gpu_capabilities = if gpu, do: [:gpu], else: []

    model_capabilities =
      case model_type do
        :transformer -> [:nlp, :text_generation]
        :cnn -> [:computer_vision, :image_processing]
        :llm -> [:language_modeling, :text_generation, :reasoning]
        :general -> [:general_ml]
        _ -> [model_type]
      end

    all_capabilities = base_capabilities ++ gpu_capabilities ++ model_capabilities

    %{
      id: id,
      type: :ml_agent,
      module: Foundation.TestHelpers.MLWorker,
      args: [model_type: model_type, frameworks: frameworks],
      capabilities: all_capabilities,
      restart_policy: :permanent,
      metadata: %{
        model_type: model_type,
        gpu_enabled: gpu,
        memory_requirement_gb: memory_gb,
        frameworks: frameworks,
        inference_ready: true,
        training_capable: true,
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Create a coordination agent configuration.

  Coordination agents manage other agents and handle orchestration tasks.
  They typically have elevated privileges and coordination capabilities.

  ## Parameters
  - `id` - Agent identifier (default: :coord_agent)
  - `opts` - Coordination options

  ## Options
  - `:max_managed_agents` - Maximum agents this coordinator can manage (default: 10)
  - `:coordination_strategy` - Strategy for coordination (default: :round_robin)
  - `:load_balancing` - Load balancing enabled (default: true)

  ## Examples

      config = coordination_agent_config()
      config = coordination_agent_config(:ml_coordinator,
        max_managed_agents: 50,
        coordination_strategy: :priority_based
      )
  """
  @spec coordination_agent_config(atom(), keyword()) :: agent_config()
  def coordination_agent_config(id \\ :coord_agent, opts \\ []) do
    max_managed = Keyword.get(opts, :max_managed_agents, 10)
    strategy = Keyword.get(opts, :coordination_strategy, :round_robin)
    load_balancing = Keyword.get(opts, :load_balancing, true)

    %{
      id: id,
      type: :coordinator,
      module: Foundation.TestHelpers.CoordinationAgent,
      args: [strategy: strategy, max_managed: max_managed],
      capabilities: [:coordination, :management, :load_balancing, :monitoring],
      restart_policy: :permanent,
      metadata: %{
        max_managed_agents: max_managed,
        coordination_strategy: strategy,
        load_balancing_enabled: load_balancing,
        managed_agents: [],
        coordinator_level: 1,
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Create a failing agent configuration for error testing.

  Failing agents are designed to fail in predictable ways for testing
  error handling, recovery, and fault tolerance scenarios.

  ## Parameters
  - `id` - Agent identifier (default: :failing_agent)
  - `opts` - Failure configuration options

  ## Options
  - `:failure_mode` - How the agent should fail (default: :immediate)
  - `:failure_rate` - Probability of failure (0.0 to 1.0, default: 1.0)
  - `:recovery_time` - Time before attempting recovery (default: 1000ms)

  ## Failure Modes
  - `:immediate` - Fails immediately on start
  - `:delayed` - Fails after a delay
  - `:random` - Fails randomly based on failure_rate
  - `:timeout` - Fails to respond to messages
  - `:memory_leak` - Gradually consumes memory
  - `:crash_loop` - Repeatedly crashes and restarts

  ## Examples

      config = failing_agent_config()
      config = failing_agent_config(:flaky_worker,
        failure_mode: :random,
        failure_rate: 0.3
      )
  """
  @spec failing_agent_config(atom(), keyword()) :: agent_config()
  def failing_agent_config(id \\ :failing_agent, opts \\ []) do
    failure_mode = Keyword.get(opts, :failure_mode, :immediate)
    failure_rate = Keyword.get(opts, :failure_rate, 1.0)
    recovery_time = Keyword.get(opts, :recovery_time, 1000)

    %{
      id: id,
      type: :failing_agent,
      module: Foundation.TestHelpers.FailingAgent,
      args: [
        failure_mode: failure_mode,
        failure_rate: failure_rate,
        recovery_time: recovery_time
      ],
      capabilities: [:compute, :failure_testing],
      restart_policy: :temporary,
      metadata: %{
        failure_mode: failure_mode,
        failure_rate: failure_rate,
        recovery_time_ms: recovery_time,
        test_agent: true,
        expected_failures: true,
        created_at: DateTime.utc_now()
      }
    }
  end

  # ============================================================================
  # Specialized Agent Configurations
  # ============================================================================

  @doc """
  Create an NLP (Natural Language Processing) agent configuration.

  ## Examples

      config = nlp_agent_config(:text_processor)
      config = nlp_agent_config(:chatbot, model: :gpt, languages: [:en, :es])
  """
  @spec nlp_agent_config(atom(), keyword()) :: agent_config()
  def nlp_agent_config(id \\ :nlp_agent, opts \\ []) do
    model = Keyword.get(opts, :model, :transformer)
    languages = Keyword.get(opts, :languages, [:en])
    tasks = Keyword.get(opts, :tasks, [:text_classification, :sentiment_analysis])

    ml_agent_config(id,
      model_type: :transformer,
      gpu: true,
      frameworks: [:huggingface, :spacy]
    )
    |> put_in([:metadata, :nlp_model], model)
    |> put_in([:metadata, :supported_languages], languages)
    |> put_in([:metadata, :nlp_tasks], tasks)
    |> Map.put(:type, :nlp_agent)
  end

  @doc """
  Create a computer vision agent configuration.

  ## Examples

      config = vision_agent_config(:image_classifier)
      config = vision_agent_config(:object_detector,
        model: :yolo,
        input_formats: [:jpg, :png, :tiff]
      )
  """
  @spec vision_agent_config(atom(), keyword()) :: agent_config()
  def vision_agent_config(id \\ :vision_agent, opts \\ []) do
    model = Keyword.get(opts, :model, :cnn)
    input_formats = Keyword.get(opts, :input_formats, [:jpg, :png])
    tasks = Keyword.get(opts, :tasks, [:classification, :detection])

    ml_agent_config(id,
      model_type: :cnn,
      gpu: true,
      memory_gb: 8,
      frameworks: [:pytorch, :opencv]
    )
    |> put_in([:metadata, :vision_model], model)
    |> put_in([:metadata, :input_formats], input_formats)
    |> put_in([:metadata, :vision_tasks], tasks)
    |> Map.put(:type, :vision_agent)
  end

  @doc """
  Create a data processing agent configuration.

  ## Examples

      config = data_agent_config(:etl_processor)
      config = data_agent_config(:stream_processor,
        throughput: :high,
        formats: [:json, :parquet, :csv]
      )
  """
  @spec data_agent_config(atom(), keyword()) :: agent_config()
  def data_agent_config(id \\ :data_agent, opts \\ []) do
    throughput = Keyword.get(opts, :throughput, :medium)
    formats = Keyword.get(opts, :formats, [:json, :csv])
    streaming = Keyword.get(opts, :streaming, false)

    basic_worker_config(id, capabilities: [:compute, :data_processing, :io])
    |> put_in([:metadata, :throughput_level], throughput)
    |> put_in([:metadata, :supported_formats], formats)
    |> put_in([:metadata, :streaming_capable], streaming)
    |> Map.put(:type, :data_agent)
  end

  # ============================================================================
  # Complex Scenario Configurations
  # ============================================================================

  @doc """
  Create configurations for multiple agents with different capabilities.

  This is useful for testing agent discovery, coordination, and capability
  matching scenarios.

  ## Parameters
  - `count` - Number of agents to create (default: 5)
  - `opts` - Configuration options

  ## Options
  - `:base_name` - Base name for agent IDs (default: :multi_agent)
  - `:vary_capabilities` - Generate different capabilities per agent (default: true)
  - `:include_coordinators` - Include coordination agents (default: false)

  ## Examples

      configs = multi_capability_agent_configs()
      configs = multi_capability_agent_configs(10, include_coordinators: true)
  """
  @spec multi_capability_agent_configs(pos_integer(), keyword()) :: [agent_config()]
  def multi_capability_agent_configs(count \\ 5, opts \\ []) do
    base_name = Keyword.get(opts, :base_name, :multi_agent)
    vary_capabilities = Keyword.get(opts, :vary_capabilities, true)
    include_coordinators = Keyword.get(opts, :include_coordinators, false)

    coordinator_count = if include_coordinators, do: max(1, div(count, 5)), else: 0
    worker_count = count - coordinator_count

    # Create coordinators
    coordinators =
      if coordinator_count > 0 do
        1..coordinator_count
        |> Enum.map(fn i ->
          coordination_agent_config(:"#{base_name}_coordinator_#{i}")
        end)
      else
        []
      end

    # Create workers with varied capabilities
    workers =
      1..worker_count
      |> Enum.map(fn i ->
        agent_id = :"#{base_name}_worker_#{i}"

        if vary_capabilities do
          case rem(i, 4) do
            0 -> basic_worker_config(agent_id)
            1 -> ml_agent_config(agent_id, model_type: :general)
            2 -> nlp_agent_config(agent_id)
            3 -> vision_agent_config(agent_id)
          end
        else
          basic_worker_config(agent_id)
        end
      end)

    coordinators ++ workers
  end

  @doc """
  Create configurations for resource-intensive agents.

  These agents are designed to test resource management, load balancing,
  and performance under heavy computational loads.

  ## Parameters
  - `count` - Number of agents (default: 10)
  - `opts` - Resource configuration options

  ## Options
  - `:memory_gb` - Memory requirement per agent (default: 8)
  - `:cpu_cores` - CPU cores per agent (default: 4)
  - `:gpu` - GPU requirement (default: false)

  ## Examples

      configs = resource_intensive_agent_configs()
      configs = resource_intensive_agent_configs(5, memory_gb: 16, gpu: true)
  """
  @spec resource_intensive_agent_configs(pos_integer(), keyword()) :: [agent_config()]
  def resource_intensive_agent_configs(count \\ 10, opts \\ []) do
    memory_gb = Keyword.get(opts, :memory_gb, 8)
    cpu_cores = Keyword.get(opts, :cpu_cores, 4)
    gpu = Keyword.get(opts, :gpu, false)

    1..count
    |> Enum.map(fn i ->
      agent_id = :"resource_intensive_agent_#{i}"

      ml_agent_config(agent_id,
        memory_gb: memory_gb,
        gpu: gpu,
        model_type: :large_model
      )
      |> put_in([:metadata, :cpu_cores_required], cpu_cores)
      |> put_in([:metadata, :resource_intensive], true)
      |> put_in([:metadata, :priority], :high)
    end)
  end

  @doc """
  Create configurations for distributed agents across multiple nodes.

  ## Parameters
  - `node_count` - Number of nodes to distribute across (default: 3)
  - `agents_per_node` - Agents per node (default: 5)
  - `opts` - Distribution options

  ## Examples

      configs = distributed_agent_configs()
      configs = distributed_agent_configs(5, 10, coordinator_nodes: [:node1])
  """
  @spec distributed_agent_configs(pos_integer(), pos_integer(), keyword()) :: [agent_config()]
  def distributed_agent_configs(node_count \\ 3, agents_per_node \\ 5, opts \\ []) do
    coordinator_nodes = Keyword.get(opts, :coordinator_nodes, [])

    1..node_count
    |> Enum.flat_map(fn node_id ->
      node_name = :"node_#{node_id}"

      1..agents_per_node
      |> Enum.map(fn agent_idx ->
        agent_id = :"distributed_agent_#{node_id}_#{agent_idx}"

        base_config =
          if node_name in coordinator_nodes do
            coordination_agent_config(agent_id)
          else
            basic_worker_config(agent_id)
          end

        base_config
        |> put_in([:metadata, :target_node], node_name)
        |> put_in([:metadata, :distributed], true)
        |> put_in([:metadata, :node_affinity], node_name)
      end)
    end)
  end

  # ============================================================================
  # Load Testing Configurations
  # ============================================================================

  @doc """
  Create configurations optimized for load testing scenarios.

  ## Parameters
  - `count` - Number of agents (default: 100)
  - `opts` - Load testing options

  ## Options
  - `:lightweight` - Use minimal resource configurations (default: true)
  - `:realistic_metadata` - Include realistic metadata sizes (default: false)

  ## Examples

      configs = load_test_agent_configs(1000)
      configs = load_test_agent_configs(500, realistic_metadata: true)
  """
  @spec load_test_agent_configs(pos_integer(), keyword()) :: [agent_config()]
  def load_test_agent_configs(count \\ 100, opts \\ []) do
    lightweight = Keyword.get(opts, :lightweight, true)
    realistic_metadata = Keyword.get(opts, :realistic_metadata, false)

    1..count
    |> Enum.map(fn i ->
      agent_id = :"load_test_agent_#{i}"

      base_config =
        if lightweight do
          basic_worker_config(agent_id, capabilities: [:compute])
        else
          # Mix of different agent types for realistic load
          case rem(i, 3) do
            0 -> basic_worker_config(agent_id)
            1 -> ml_agent_config(agent_id, gpu: false, memory_gb: 2)
            2 -> data_agent_config(agent_id)
          end
        end

      if realistic_metadata do
        # Add larger metadata to simulate real-world scenarios
        large_metadata = %{
          description: "Load testing agent with realistic metadata size",
          configuration: %{
            batch_size: 32,
            learning_rate: 0.001,
            epochs: 100,
            optimizer: :adam,
            loss_function: :cross_entropy
          },
          performance_history:
            Enum.map(1..10, fn epoch ->
              %{epoch: epoch, loss: :rand.uniform(), accuracy: :rand.uniform()}
            end),
          last_updated: DateTime.utc_now(),
          version: "1.0.0"
        }

        Map.update!(base_config, :metadata, fn existing ->
          Map.merge(existing, large_metadata)
        end)
      else
        base_config
      end
    end)
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Create a random agent configuration for property-based testing.

  ## Examples

      config = random_agent_config()
      config = random_agent_config(seed: 12345)
  """
  @spec random_agent_config(keyword()) :: agent_config()
  def random_agent_config(opts \\ []) do
    seed = Keyword.get(opts, :seed)
    if seed, do: :rand.seed(:exsss, {seed, seed, seed})

    agent_types = [:worker, :ml_agent, :coordinator, :nlp_agent, :vision_agent, :data_agent]
    agent_type = Enum.random(agent_types)
    agent_id = :"random_agent_#{System.unique_integer([:positive])}"

    case agent_type do
      :worker -> basic_worker_config(agent_id)
      :ml_agent -> ml_agent_config(agent_id, random_ml_options())
      :coordinator -> coordination_agent_config(agent_id)
      :nlp_agent -> nlp_agent_config(agent_id)
      :vision_agent -> vision_agent_config(agent_id)
      :data_agent -> data_agent_config(agent_id)
    end
  end

  @doc """
  Validate that an agent configuration is well-formed.

  ## Parameters
  - `config` - Agent configuration to validate

  ## Returns
  - `:ok` if valid
  - `{:error, reason}` if invalid

  ## Examples

      :ok = validate_agent_config(config)
      {:error, "Missing required field: id"} = validate_agent_config(%{})
  """
  @spec validate_agent_config(agent_config()) :: :ok | {:error, String.t()}
  def validate_agent_config(config) when is_map(config) do
    required_fields = [:id, :type, :module, :args, :capabilities, :restart_policy, :metadata]

    missing_fields = required_fields -- Map.keys(config)

    case missing_fields do
      [] ->
        validate_field_types(config)

      missing ->
        {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end

  def validate_agent_config(_), do: {:error, "Configuration must be a map"}

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Generate random ML options for property testing
  defp random_ml_options do
    model_types = [:general, :transformer, :cnn, :llm]
    frameworks = [[:pytorch], [:tensorflow], [:huggingface], [:pytorch, :tensorflow]]

    [
      model_type: Enum.random(model_types),
      gpu: Enum.random([true, false]),
      memory_gb: Enum.random([2, 4, 8, 16]),
      frameworks: Enum.random(frameworks)
    ]
  end

  # Validate field types in agent configuration
  defp validate_field_types(config) do
    validations = [
      {:id, &is_atom/1, "id must be an atom"},
      {:type, &is_atom/1, "type must be an atom"},
      {:module, &is_atom/1, "module must be an atom"},
      {:args, &is_list/1, "args must be a list"},
      {:capabilities, &is_list/1, "capabilities must be a list"},
      {:restart_policy, &is_atom/1, "restart_policy must be an atom"},
      {:metadata, &is_map/1, "metadata must be a map"}
    ]

    Enum.reduce_while(validations, :ok, fn {field, validator, error_msg}, _acc ->
      value = Map.get(config, field)

      if validator.(value) do
        {:cont, :ok}
      else
        {:halt, {:error, error_msg}}
      end
    end)
  end
end
