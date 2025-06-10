# Foundation.Config 2.0 - Distributed Configuration Intelligence
# lib/foundation/services/config_server.ex
defmodule Foundation.Services.ConfigServer do
  use GenServer
  require Logger

  # ✅ BACKWARD COMPATIBILITY: All original APIs unchanged
  # ✅ NEW FEATURES: Distributed consensus, adaptive learning, conflict resolution
  
  defstruct [
    :namespace,
    :local_config,
    :cluster_config,
    :consensus_state,
    :learning_engine,
    :conflict_resolver,
    :subscription_manager
  ]

  ## Original Foundation 1.x APIs (100% Compatible)
  
  def get(path, opts \\ []) do
    GenServer.call(__MODULE__, {:get, path, opts})
  end
  
  def update(path, value, opts \\ []) do
    GenServer.call(__MODULE__, {:update, path, value, opts})
  end
  
  def available?() do
    GenServer.call(__MODULE__, :available?)
  end
  
  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  ## Enhanced Foundation 2.0 APIs (Additive)
  
  def set_cluster_wide(path, value, opts \\ []) do
    GenServer.call(__MODULE__, {:set_cluster_wide, path, value, opts})
  end
  
  def get_with_consensus(path, opts \\ []) do
    GenServer.call(__MODULE__, {:get_with_consensus, path, opts})
  end
  
  def enable_adaptive_config(strategies \\ [:auto_optimize, :predict_needs]) do
    GenServer.call(__MODULE__, {:enable_adaptive_config, strategies})
  end
  
  def resolve_config_conflicts(strategy \\ :intelligent_merge) do
    GenServer.call(__MODULE__, {:resolve_conflicts, strategy})
  end

  ## GenServer Implementation
  
  def start_link(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :default)
    GenServer.start_link(__MODULE__, namespace, name: __MODULE__)
  end

  @impl true
  def init(namespace) do
    state = %__MODULE__{
      namespace: namespace,
      local_config: load_local_config(namespace),
      cluster_config: %{},
      consensus_state: initialize_consensus(),
      learning_engine: initialize_learning_engine(),
      conflict_resolver: initialize_conflict_resolver(),
      subscription_manager: initialize_subscriptions()
    }
    
    # Join cluster configuration network
    if cluster_enabled?() do
      join_config_cluster(namespace)
    end
    
    {:ok, state}
  end

  ## Original API Handlers (Unchanged Behavior)
  
  @impl true
  def handle_call({:get, path, opts}, _from, state) do
    case get_local_value(state.local_config, path) do
      {:ok, value} -> {:reply, {:ok, value}, state}
      :not_found -> {:reply, :not_found, state}
    end
  end
  
  @impl true
  def handle_call({:update, path, value, opts}, _from, state) do
    case update_local_config(state.local_config, path, value) do
      {:ok, new_config} ->
        new_state = %{state | local_config: new_config}
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, true, state}
  end
  
  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{state | local_config: %{}}
    {:reply, :ok, new_state}
  end

  ## Enhanced API Handlers (New Distributed Features)
  
  @impl true
  def handle_call({:set_cluster_wide, path, value, opts}, _from, state) do
    case propose_cluster_config_change(path, value, opts, state) do
      {:ok, new_cluster_config} ->
        new_state = %{state | cluster_config: new_cluster_config}
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:get_with_consensus, path, opts}, _from, state) do
    case get_consensus_value(path, opts, state) do
      {:ok, value} -> {:reply, {:ok, value}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:enable_adaptive_config, strategies}, _from, state) do
    new_learning_engine = enable_learning_strategies(state.learning_engine, strategies)
    new_state = %{state | learning_engine: new_learning_engine}
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:resolve_conflicts, strategy}, _from, state) do
    case resolve_pending_conflicts(state.conflict_resolver, strategy) do
      {:ok, resolutions} ->
        apply_conflict_resolutions(resolutions, state)
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  ## Distributed Configuration Implementation
  
  defp propose_cluster_config_change(path, value, opts, state) do
    proposal = %{
      path: path,
      value: value,
      opts: opts,
      proposer: Node.self(),
      timestamp: :os.system_time(:millisecond)
    }
    
    case Foundation.Distributed.Consensus.propose(proposal) do
      {:ok, accepted} ->
        Logger.info("Cluster config change accepted: #{inspect(path)} = #{inspect(value)}")
        {:ok, apply_consensus_change(state.cluster_config, accepted)}
      {:error, reason} ->
        Logger.warning("Cluster config change rejected: #{reason}")
        {:error, reason}
    end
  end
  
  defp get_consensus_value(path, opts, state) do
    timeout = Keyword.get(opts, :timeout, 5000)
    required_nodes = Keyword.get(opts, :required_nodes, majority_nodes())
    
    case Foundation.Distributed.Consensus.get_value(path, required_nodes, timeout) do
      {:ok, value} -> {:ok, value}
      {:timeout, partial_responses} ->
        # Use conflict resolution for partial responses
        resolve_partial_consensus(partial_responses, state.conflict_resolver)
      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Adaptive Configuration Learning
  
  defp initialize_learning_engine() do
    %{
      enabled_strategies: [],
      config_usage_patterns: %{},
      optimization_history: [],
      prediction_models: %{}
    }
  end
  
  defp enable_learning_strategies(engine, strategies) do
    Enum.reduce(strategies, engine, fn strategy, acc ->
      case strategy do
        :auto_optimize ->
          %{acc | enabled_strategies: [:auto_optimize | acc.enabled_strategies]}
        :predict_needs ->
          %{acc | enabled_strategies: [:predict_needs | acc.enabled_strategies]}
        :detect_conflicts ->
          %{acc | enabled_strategies: [:detect_conflicts | acc.enabled_strategies]}
      end
    end)
  end

  ## Intelligent Conflict Resolution
  
  defp initialize_conflict_resolver() do
    %{
      resolution_strategies: [:timestamp_wins, :majority_wins, :intelligent_merge],
      pending_conflicts: [],
      resolution_history: []
    }
  end
  
  defp resolve_pending_conflicts(resolver, strategy) do
    conflicts = resolver.pending_conflicts
    
    resolutions = Enum.map(conflicts, fn conflict ->
      case strategy do
        :intelligent_merge ->
          intelligent_merge_conflict(conflict)
        :majority_wins ->
          majority_wins_resolution(conflict)
        :timestamp_wins ->
          timestamp_wins_resolution(conflict)
      end
    end)
    
    {:ok, resolutions}
  end
  
  defp intelligent_merge_conflict(conflict) do
    # Use AI-powered conflict resolution
    case Foundation.Intelligence.ConfigMerger.resolve(conflict) do
      {:ok, merged_value} ->
        %{
          conflict_id: conflict.id,
          resolution: :merged,
          value: merged_value,
          confidence: 0.85
        }
      {:error, _reason} ->
        # Fall back to timestamp wins
        timestamp_wins_resolution(conflict)
    end
  end

  ## Cluster Membership Management
  
  defp cluster_enabled?() do
    Application.get_env(:foundation, :distributed_config, false)
  end
  
  defp join_config_cluster(namespace) do
    Foundation.Distributed.ConfigCluster.join(namespace)
  end
  
  defp majority_nodes() do
    all_nodes = [Node.self() | Node.list()]
    div(length(all_nodes), 2) + 1
  end

  ## Local Configuration Management (Foundation 1.x Compatible)
  
  defp load_local_config(namespace) do
    config_file = Application.get_env(:foundation, :config_file)
    case File.read(config_file) do
      {:ok, content} -> 
        :erlang.binary_to_term(content)
      {:error, _} -> 
        %{}
    end
  end
  
  defp get_local_value(config, path) do
    case get_in(config, path) do
      nil -> :not_found
      value -> {:ok, value}
    end
  end
  
  defp update_local_config(config, path, value) do
    try do
      new_config = put_in(config, path, value)
      {:ok, new_config}
    rescue
      e -> {:error, {:invalid_path, e}}
    end
  end

  # Stub implementations for missing functions
  defp initialize_consensus(), do: %{}
  defp initialize_subscriptions(), do: %{}
  defp apply_consensus_change(config, _change), do: config
  defp resolve_partial_consensus(_responses, _resolver), do: {:error, :timeout}
  defp apply_conflict_resolutions(_resolutions, state), do: {:reply, :ok, state}
  defp majority_wins_resolution(_conflict), do: %{}
  defp timestamp_wins_resolution(_conflict), do: %{}
end
