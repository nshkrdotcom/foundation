defmodule Foundation.AgentTestHelpers do
  @moduledoc """
  Test helpers for agent-aware testing scenarios.

  Provides utilities for creating test agents, managing agent lifecycles,
  and setting up common test scenarios for agent-aware infrastructure.
  """

  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo
  alias Foundation.Infrastructure.{AgentCircuitBreaker, AgentRateLimiter, ResourceManager}
  alias Foundation.Services.{EventStore, TelemetryService}

  @doc """
  Starts a test agent with specified capabilities and health.

  Returns a tuple of {pid, metadata} for easy cleanup.
  """
  def start_test_agent(agent_id, capabilities \\ [:general], health \\ :healthy, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, {:test, make_ref()})

    pid = spawn(fn ->
      receive do
        :stop -> :ok
      after
        Keyword.get(opts, :lifetime, 30_000) -> :ok
      end
    end)

    resource_usage = Keyword.get(opts, :resource_usage, %{
      memory: 0.5,
      cpu: 0.3,
      network: 10,
      storage: 0.2
    })

    coordination_state = Keyword.get(opts, :coordination_state, %{
      active_consensus: [],
      active_barriers: [],
      held_locks: [],
      leadership_roles: []
    })

    metadata = %AgentInfo{
      agent_id: agent_id,
      state: Keyword.get(opts, :state, :ready),
      capabilities: capabilities,
      health_metrics: health,
      resource_usage: resource_usage,
      performance_metrics: %{},
      coordination_state: coordination_state,
      configuration: Keyword.get(opts, :configuration, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now(),
      last_updated: DateTime.utc_now(),
      version: 1
    }

    ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)

    {pid, metadata}
  end

  @doc """
  Stops a test agent and cleans up its registration.
  """
  def stop_test_agent(agent_id, pid, namespace \\ {:test, make_ref()}) do
    send(pid, :stop)
    ProcessRegistry.unregister(namespace, agent_id)
  end

  @doc """
  Updates an agent's health status.
  """
  def update_agent_health(agent_id, new_health, namespace \\ {:test, make_ref()}) do
    {:ok, {pid, metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
    updated_metadata = %AgentInfo{
      metadata |
      health_metrics: %{status: new_health},
      last_updated: DateTime.utc_now()
    }
    ProcessRegistry.update_agent_metadata(namespace, agent_id, updated_metadata)
  end

  @doc """
  Updates an agent's resource usage.
  """
  def update_agent_resources(agent_id, new_resource_usage, namespace \\ {:test, make_ref()}) do
    {:ok, {pid, metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
    updated_metadata = %AgentInfo{metadata | resource_usage: new_resource_usage, last_updated: DateTime.utc_now()}
    ProcessRegistry.update_agent_metadata(namespace, agent_id, updated_metadata)
  end

  @doc """
  Creates a coordination scenario with multiple agents.
  """
  def create_agent_coordination_scenario(agent_ids, coordination_type \\ :consensus, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, {:test, make_ref()})

    agents = for agent_id <- agent_ids do
      capabilities = case coordination_type do
        :consensus -> [:coordination, :voting]
        :resource_allocation -> [:resource_management]
        :leader_election -> [:leadership]
        _ -> [:coordination]
      end

      {pid, metadata} = start_test_agent(
        agent_id,
        capabilities,
        :healthy,
        [namespace: namespace] ++ opts
      )
      {agent_id, pid, metadata}
    end

    coordination_id = :"test_coordination_#{:rand.uniform(1000)}"

    {agents, coordination_id, namespace}
  end

  @doc """
  Cleans up multiple agents from a coordination scenario.
  """
  def cleanup_agents(agents, namespace \\ {:test, make_ref()}) do
    for {agent_id, pid, _metadata} <- agents do
      stop_test_agent(agent_id, pid, namespace)
    end
  end

  @doc """
  Sets up a complete infrastructure environment for testing.
  """
  def setup_agent_infrastructure(agents_config, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, {:test, make_ref()})

    # Start infrastructure services if not already started
    services = []

    services = if Keyword.get(opts, :rate_limiter, true) do
      rate_limits = Keyword.get(opts, :rate_limits, %{
        inference: %{requests: 10, window: 1000},
        training: %{requests: 5, window: 2000}
      })

      case AgentRateLimiter.start_link([rate_limits: rate_limits]) do
        {:ok, pid} -> [{:rate_limiter, pid} | services]
        {:error, {:already_started, pid}} -> [{:rate_limiter, pid} | services]
      end
    else
      services
    end

    services = if Keyword.get(opts, :resource_manager, true) do
      case ResourceManager.start_link([
        monitoring_interval: 100,
        system_thresholds: %{memory: %{warning: 0.8, critical: 0.9}}
      ]) do
        {:ok, pid} -> [{:resource_manager, pid} | services]
        {:error, {:already_started, pid}} -> [{:resource_manager, pid} | services]
      end
    else
      services
    end

    # Register agents and set up infrastructure
    agents = for {agent_id, config} <- agents_config do
      capabilities = Map.get(config, :capabilities, [:general])
      health = Map.get(config, :health, :healthy)
      resource_limits = Map.get(config, :resource_limits, %{
        memory_limit: 1_000_000_000,
        cpu_limit: 1.0
      })

      {pid, metadata} = start_test_agent(
        agent_id,
        capabilities,
        health,
        [namespace: namespace] ++ Map.to_list(config)
      )

      # Set up resource management
      if Keyword.get(opts, :resource_manager, true) do
        ResourceManager.register_agent(agent_id, resource_limits)
      end

      # Set up circuit breakers
      if Keyword.get(opts, :circuit_breakers, true) do
        for capability <- capabilities do
          AgentCircuitBreaker.start_agent_breaker(
            :"#{capability}_service",
            agent_id: agent_id,
            capability: capability,
            namespace: namespace
          )
        end
      end

      {agent_id, pid, metadata}
    end

    %{
      agents: agents,
      services: services,
      namespace: namespace
    }
  end

  @doc """
  Cleans up a complete infrastructure environment.
  """
  def cleanup_agent_infrastructure(%{agents: agents, services: services, namespace: namespace}) do
    # Cleanup agents
    for {agent_id, pid, _metadata} <- agents do
      stop_test_agent(agent_id, pid, namespace)

      # Cleanup resource manager registration
      try do
        ResourceManager.unregister_agent(agent_id)
      rescue
        _ -> :ok
      end
    end

    # Cleanup services (optional - they might be shared)
    # for {service_type, pid} <- services do
    #   try do
    #     GenServer.stop(pid)
    #   rescue
    #     _ -> :ok
    #   end
    # end
  end

  @doc """
  Generates test events for an agent.
  """
  def generate_test_events(agent_id, event_types, count \\ 5) do
    correlation_id = "test_correlation_#{:rand.uniform(1000)}"

    for i <- 1..count do
      event_type = Enum.random(event_types)

      %Foundation.Types.Event{
        id: "test_event_#{agent_id}_#{i}",
        type: event_type,
        agent_context: %{agent_id: agent_id},
        data: %{
          sequence: i,
          test_data: "generated_event",
          random_value: :rand.uniform(100)
        },
        correlation_id: correlation_id,
        timestamp: DateTime.add(DateTime.utc_now(), i, :second)
      }
    end
  end

  @doc """
  Records test telemetry metrics for an agent.
  """
  def record_test_metrics(agent_id, metric_specs, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, {:test, make_ref()})

    for {metric_name, metric_type, values} <- metric_specs do
      for value <- values do
        TelemetryService.record_metric(
          metric_name,
          value,
          metric_type,
          %{
            agent_id: agent_id,
            namespace: namespace,
            test_context: true
          }
        )
      end
    end

    # Trigger aggregation if requested
    if Keyword.get(opts, :trigger_aggregation, true) do
      TelemetryService.trigger_aggregation()
    end
  end

  @doc """
  Simulates agent failure scenarios.
  """
  def simulate_agent_failure(agent_id, failure_type, namespace \\ {:test, make_ref()}) do
    case failure_type do
      :health_degradation ->
        update_agent_health(agent_id, :unhealthy, namespace)
        update_agent_resources(agent_id, %{memory: 0.95, cpu: 0.9}, namespace)

      :resource_exhaustion ->
        update_agent_resources(agent_id, %{memory: 0.99, cpu: 0.95}, namespace)
        update_agent_health(agent_id, :degraded, namespace)

      :critical_failure ->
        update_agent_health(agent_id, :critical, namespace)
        update_agent_resources(agent_id, %{memory: 0.99, cpu: 0.99}, namespace)

      :process_termination ->
        {:ok, {pid, _metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
        Process.exit(pid, :kill)

      _ ->
        {:error, :unknown_failure_type}
    end
  end

  @doc """
  Waits for a condition to be met with timeout.
  """
  def wait_for_condition(condition_fn, timeout \\ 5000, check_interval \\ 100) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_condition_loop(condition_fn, end_time, check_interval)
  end

  defp wait_for_condition_loop(condition_fn, end_time, check_interval) do
    if condition_fn.() do
      :ok
    else
      current_time = System.monotonic_time(:millisecond)
      if current_time >= end_time do
        {:error, :timeout}
      else
        Process.sleep(check_interval)
        wait_for_condition_loop(condition_fn, end_time, check_interval)
      end
    end
  end

  @doc """
  Asserts that a condition becomes true within a timeout.
  """
  defmacro assert_eventually(condition, timeout \\ 5000) do
    quote do
      result = Foundation.AgentTestHelpers.wait_for_condition(
        fn -> unquote(condition) end,
        unquote(timeout)
      )

      case result do
        :ok -> :ok
        {:error, :timeout} ->
          ExUnit.Assertions.flunk(
            "Condition did not become true within #{unquote(timeout)}ms: #{unquote(Macro.to_string(condition))}"
          )
      end
    end
  end

  @doc """
  Creates a mock implementation for testing.
  """
  def create_mock_implementation(module, functions) do
    for {function_name, arity, mock_impl} <- functions do
      :meck.new(module, [:non_strict])
      :meck.expect(module, function_name, arity, mock_impl)
    end
  end

  @doc """
  Validates that an agent infrastructure setup is healthy.
  """
  def validate_infrastructure_health(infrastructure) do
    %{agents: agents, namespace: namespace} = infrastructure

    # Check all agents are registered and accessible
    for {agent_id, _pid, _metadata} <- agents do
      assert {:ok, {_pid, _metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
    end

    # Check system health overview
    {:ok, health_overview} = ProcessRegistry.get_system_health_overview(namespace)
    assert health_overview.total_agents == length(agents)
    assert health_overview.health_percentage >= 0.0

    :ok
  end

  @doc """
  Generates realistic load patterns for testing.
  """
  def generate_load_pattern(pattern_type, duration_ms, agents) do
    case pattern_type do
      :constant ->
        interval = div(duration_ms, 100)  # 100 operations over duration
        for _i <- 1..100 do
          {Enum.random(agents), :inference, %{}, interval}
        end

      :burst ->
        # Generate 50 operations in first 10% of time, then sparse
        burst_count = 50
        sparse_count = 20
        burst_duration = div(duration_ms, 10)
        sparse_duration = duration_ms - burst_duration

        burst_ops = for _i <- 1..burst_count do
          {Enum.random(agents), :inference, %{burst: true}, div(burst_duration, burst_count)}
        end

        sparse_ops = for _i <- 1..sparse_count do
          {Enum.random(agents), :inference, %{sparse: true}, div(sparse_duration, sparse_count)}
        end

        burst_ops ++ sparse_ops

      :ramp_up ->
        # Gradually increase load over time
        for i <- 1..100 do
          interval = max(10, div(duration_ms, i))  # Decreasing intervals
          {Enum.random(agents), :inference, %{ramp_position: i}, interval}
        end

      _ ->
        []
    end
  end
end