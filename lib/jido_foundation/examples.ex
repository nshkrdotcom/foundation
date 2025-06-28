defmodule JidoFoundation.Examples do
  @moduledoc """
  Example integration patterns showing how Jido agents can leverage Foundation infrastructure.
  
  These examples demonstrate:
  - Agent lifecycle management with Foundation registration
  - Circuit breaker protection for external calls
  - Resource-aware agent operations
  - Multi-agent coordination patterns
  - Health monitoring and telemetry integration
  
  Note: These are examples showing integration patterns. Actual Jido implementation
  would use the JidoFoundation.Bridge module for production use.
  """
  
  require Logger
  
  # Example 1: Basic Jido Agent with Foundation Registration
  
  defmodule SimpleJidoAgent do
    @moduledoc """
    Example of a simple Jido agent that registers with Foundation.
    """
    
    use GenServer
    
    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end
    
    def init(config) do
      # Register with Foundation on startup
      :ok = JidoFoundation.Bridge.register_agent(self(), 
        capabilities: config[:capabilities] || [:basic],
        metadata: %{
          version: "1.0",
          config: config
        }
      )
      
      {:ok, %{config: config, state: :idle}}
    end
    
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
    
    def handle_call({:execute, action}, _from, state) do
      # Emit telemetry through Foundation
      JidoFoundation.Bridge.emit_agent_event(self(), :action_started, %{}, %{action: action})
      
      result = perform_action(action, state)
      
      JidoFoundation.Bridge.emit_agent_event(self(), :action_completed, 
        %{duration: :rand.uniform(100)}, 
        %{action: action, success: elem(result, 0) == :ok}
      )
      
      {:reply, result, state}
    end
    
    defp perform_action(:compute, _state) do
      # Simulate computation
      Process.sleep(:rand.uniform(50))
      {:ok, :computed}
    end
    
    defp perform_action(_, _state) do
      {:error, :unknown_action}
    end
  end
  
  # Example 2: Protected External Service Agent
  
  defmodule ExternalServiceAgent do
    @moduledoc """
    Example Jido agent that makes external calls protected by Foundation circuit breakers.
    """
    
    use GenServer
    
    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end
    
    def init(config) do
      # Register with specific capabilities
      :ok = JidoFoundation.Bridge.register_agent(self(),
        capabilities: [:external_api, :data_fetching],
        metadata: %{
          service_url: config[:service_url],
          timeout: config[:timeout] || 5000
        }
      )
      
      {:ok, config}
    end
    
    def handle_call({:fetch_data, endpoint}, _from, state) do
      # Use Foundation circuit breaker for protection
      result = JidoFoundation.Bridge.execute_protected(self(), fn ->
        make_external_call(state.service_url, endpoint, state.timeout)
      end,
      fallback: {:ok, :cached_data},
      service_id: {:external_api, state.service_url}
      )
      
      {:reply, result, state}
    end
    
    defp make_external_call(base_url, endpoint, _timeout) do
      # Simulate external API call
      Process.sleep(:rand.uniform(100))
      
      # Randomly fail to demonstrate circuit breaker
      if :rand.uniform() > 0.7 do
        {:error, :service_unavailable}
      else
        {:ok, %{data: "response from #{base_url}#{endpoint}"}}
      end
    end
  end
  
  # Example 3: Resource-Aware Heavy Computation Agent
  
  defmodule ComputeIntensiveAgent do
    @moduledoc """
    Example Jido agent that performs resource-intensive operations with Foundation resource management.
    """
    
    use GenServer
    
    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end
    
    def init(config) do
      :ok = JidoFoundation.Bridge.register_agent(self(),
        capabilities: [:heavy_computation, :batch_processing],
        metadata: %{
          max_batch_size: config[:max_batch_size] || 100
        }
      )
      
      {:ok, %{config: config, current_load: 0}}
    end
    
    def handle_call({:process_batch, items}, _from, state) do
      # Acquire resource before processing
      case JidoFoundation.Bridge.acquire_resource(:compute_intensive, %{
        batch_size: length(items),
        agent: self()
      }) do
        {:ok, token} ->
          # Process with resource token
          result = process_items_with_resource(items, token, state)
          
          # Always release resource
          JidoFoundation.Bridge.release_resource(token)
          
          # Update our metadata with current load
          JidoFoundation.Bridge.update_agent_metadata(self(), %{
            resources: %{
              memory_usage: calculate_memory_usage(state),
              current_load: state.current_load
            }
          })
          
          {:reply, result, state}
          
        {:error, :resource_exhausted} = error ->
          Logger.warning("Resource exhausted for batch processing")
          {:reply, error, state}
      end
    end
    
    defp process_items_with_resource(items, _token, _state) do
      # Simulate heavy processing
      results = Enum.map(items, fn item ->
        Process.sleep(10)  # Simulate work
        {:ok, item * 2}
      end)
      
      {:ok, results}
    end
    
    defp calculate_memory_usage(_state) do
      # Simulate memory calculation
      :rand.uniform()
    end
  end
  
  # Example 4: Coordinated Multi-Agent Team
  
  defmodule TeamCoordinator do
    @moduledoc """
    Example of coordinating multiple Jido agents using Foundation's query capabilities.
    """
    
    def distribute_work(work_items, capability_required) do
      # Find all healthy agents with required capability
      case JidoFoundation.Bridge.find_agents([
        {[:capability], capability_required, :eq},
        {[:health_status], :healthy, :eq}
      ]) do
        {:ok, []} ->
          {:error, :no_agents_available}
          
        {:ok, agents} ->
          # Distribute work among agents
          agent_pids = Enum.map(agents, fn {_key, pid, _metadata} -> pid end)
          
          work_chunks = chunk_work(work_items, length(agent_pids))
          
          # Assign work to each agent in parallel
          results = work_chunks
          |> Enum.zip(agent_pids)
          |> Task.async_stream(fn {chunk, agent_pid} ->
            GenServer.call(agent_pid, {:process_batch, chunk}, 10_000)
          end, max_concurrency: length(agent_pids))
          |> Enum.map(fn
            {:ok, result} -> result
            {:exit, reason} -> {:error, reason}
          end)
          
          {:ok, results}
      end
    end
    
    defp chunk_work(items, num_chunks) do
      chunk_size = div(length(items), num_chunks) + 1
      Enum.chunk_every(items, chunk_size)
    end
  end
  
  # Example 5: Health Monitoring Pattern
  
  defmodule MonitoredAgent do
    @moduledoc """
    Example Jido agent with custom health monitoring.
    """
    
    use GenServer
    
    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end
    
    def init(config) do
      # Register with custom health check
      :ok = JidoFoundation.Bridge.register_agent(self(),
        capabilities: [:monitored_service],
        health_check: &custom_health_check/1,
        health_check_interval: 5_000
      )
      
      {:ok, %{
        config: config,
        request_count: 0,
        error_count: 0,
        last_error: nil
      }}
    end
    
    def handle_call(:health_check, _from, state) do
      health = calculate_health(state)
      {:reply, health, state}
    end
    
    def handle_call({:process, _data}, _from, state) do
      # Simulate processing with possible errors
      {result, new_state} = if :rand.uniform() > 0.9 do
        error = {:error, :processing_failed}
        {error, %{state | error_count: state.error_count + 1, last_error: DateTime.utc_now()}}
      else
        {{:ok, :processed}, %{state | request_count: state.request_count + 1}}
      end
      
      {:reply, result, new_state}
    end
    
    defp custom_health_check(agent_pid) do
      try do
        GenServer.call(agent_pid, :health_check, 1000)
      catch
        :exit, _ -> :unhealthy
      end
    end
    
    defp calculate_health(state) do
      error_rate = if state.request_count > 0 do
        state.error_count / state.request_count
      else
        0
      end
      
      cond do
        error_rate > 0.5 -> :unhealthy
        error_rate > 0.1 -> :degraded
        true -> :healthy
      end
    end
  end
  
  # Example Usage Functions
  
  @doc """
  Demonstrates starting a simple agent team.
  """
  def start_agent_team(team_size \\ 3) do
    agents = for i <- 1..team_size do
      {:ok, agent} = SimpleJidoAgent.start_link(%{
        capabilities: [:compute, :team_member],
        team_id: :example_team,
        member_id: i
      })
      agent
    end
    
    Logger.info("Started agent team with #{team_size} members")
    {:ok, agents}
  end
  
  @doc """
  Demonstrates distributed computation across agents.
  """
  def distributed_computation(data_items) do
    # Ensure we have some compute agents
    {:ok, _agents} = start_agent_team(5)
    
    # Give agents time to register
    Process.sleep(100)
    
    # Distribute work
    TeamCoordinator.distribute_work(data_items, :compute)
  end
  
  @doc """
  Demonstrates circuit breaker protection.
  """
  def protected_external_calls(num_calls \\ 10) do
    # Start an external service agent
    {:ok, agent} = ExternalServiceAgent.start_link(%{
      service_url: "https://api.example.com",
      timeout: 5000
    })
    
    # Make multiple calls to trigger circuit breaker
    results = for i <- 1..num_calls do
      result = GenServer.call(agent, {:fetch_data, "/endpoint/#{i}"})
      Logger.info("Call #{i}: #{inspect(result)}")
      result
    end
    
    {:ok, results}
  end
  
  @doc """
  Demonstrates resource-aware processing.
  """
  def resource_managed_processing(batches) do
    # Start multiple compute agents
    agents = for i <- 1..3 do
      {:ok, agent} = ComputeIntensiveAgent.start_link(%{
        max_batch_size: 50,
        agent_id: i
      })
      agent
    end
    
    # Process batches with resource management
    results = batches
    |> Enum.with_index()
    |> Enum.map(fn {batch, idx} ->
      agent = Enum.at(agents, rem(idx, length(agents)))
      GenServer.call(agent, {:process_batch, batch}, 30_000)
    end)
    
    {:ok, results}
  end
end