### **Technical Remediation: `ProcessRegistry` Architecture Overhaul**

**Objective:** To refactor the `Foundation.ProcessRegistry` into a truly pluggable, state-managed system by correctly implementing the existing `Backend` behavior. This will eliminate the flawed hybrid logic and create a clean, testable, and extensible architecture.

#### **Target Architecture**

```mermaid
graph TD
    subgraph ProcessRegistry Module
        A[API Facade (Foundation.ProcessRegistry)]
    end

    subgraph Process Management
        B[Server (Foundation.ProcessRegistry.Server)]
    end

    subgraph Backend Layer
        C[Backend Behaviour]
        D[ETS Backend]
        E[OptimizedETS Backend]
        F[...Future Backends]
    end

    A -- delegates calls --> B
    B -- holds state & calls --> C
    C -- implemented by --> D
    C -- implemented by --> E

    style A fill:#ccffcc,stroke:#00ff00
    style B fill:#b3e6ff,stroke:#0077c2
    style C fill:#fff2cc,stroke:#d6b656
    style D fill:#e6ccff,stroke:#9933ff
    style E fill:#e6ccff,stroke:#9933ff
    style F fill:#e6ccff,stroke:#9933ff,stroke-dasharray: 5 5
```

-   **API Facade (`ProcessRegistry`):** Stateless module that delegates to the `Server`.
-   **Server (`ProcessRegistry.Server`):** GenServer that manages backend state.
-   **Backend Layer:** The existing `Backend` behaviour and implementations.

---

### **Implementation Plan**

#### Phase 1: Create the Server

**Action:** Create `lib/foundation/process_registry/server.ex`.

```elixir
defmodule Foundation.ProcessRegistry.Server do
  @moduledoc """
  GenServer that manages the configured backend and handles all stateful operations.
  """
  use GenServer
  require Logger

  # ============================================================================
  # Public API & Child Spec
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    backend = Keyword.get(opts, :backend, Foundation.ProcessRegistry.Backend.ETS)
    backend_opts = Keyword.get(opts, :backend_opts, [])
    
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[backend: backend, backend_opts: backend_opts]]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    backend_module = Keyword.fetch!(opts, :backend)
    backend_opts = Keyword.get(opts, :backend_opts, [])

    case backend_module.init(backend_opts) do
      {:ok, backend_state} ->
        state = %{
          backend_module: backend_module,
          backend_state: backend_state,
          start_time: System.monotonic_time()
        }
        {:ok, state}
      {:error, reason} ->
        {:stop, {:backend_init_failed, reason}}
    end
  end

  @impl true
  def handle_call({:register, key, pid, metadata}, _from, state) when is_pid(pid) and is_map(metadata) do
    if Process.alive?(pid) do
      case state.backend_module.register(state.backend_state, key, pid, metadata) do
        {:ok, new_backend_state} ->
          {:reply, :ok, %{state | backend_state: new_backend_state}}
        {:error, _reason} = error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :process_not_alive}, state}
    end
  end

  @impl true
  def handle_call({:register, _key, pid, _metadata}, _from, state) when not is_pid(pid) do
    {:reply, {:error, :invalid_pid}, state}
  end

  @impl true
  def handle_call({:register, _key, _pid, metadata}, _from, state) when not is_map(metadata) do
    {:reply, {:error, :invalid_metadata}, state}
  end

  @impl true
  def handle_call({:lookup, key}, _from, state) do
    reply = state.backend_module.lookup(state.backend_state, key)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:unregister, key}, _from, state) do
    case state.backend_module.unregister(state.backend_state, key) do
      {:ok, new_backend_state} ->
        {:reply, :ok, %{state | backend_state: new_backend_state}}
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:update_metadata, key, metadata}, _from, state) when is_map(metadata) do
    case state.backend_module.update_metadata(state.backend_state, key, metadata) do
      {:ok, new_backend_state} ->
        {:reply, :ok, %{state | backend_state: new_backend_state}}
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:list_all}, _from, state) do
    reply = state.backend_module.list_all(state.backend_state)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:health_check}, _from, state) do
    backend_health = state.backend_module.health_check(state.backend_state)
    
    server_health = %{
      status: :healthy,
      backend_module: state.backend_module,
      uptime_ms: System.monotonic_time() - state.start_time,
      backend_health: backend_health
    }
    
    {:reply, {:ok, server_health}, state}
  end

  @impl true
  def handle_call({:get_stats}, _from, state) do
    case state.backend_module.list_all(state.backend_state) do
      {:ok, all_registrations} ->
        stats = %{
          total_registrations: length(all_registrations),
          backend_module: state.backend_module,
          uptime_ms: System.monotonic_time() - state.start_time
        }
        {:reply, {:ok, stats}, state}
      error ->
        {:reply, error, state}
    end
  end
end
```

#### Phase 2: Refactor the Main Module

**Action:** Update `lib/foundation/process_registry.ex`.

```elixir
defmodule Foundation.ProcessRegistry do
  @moduledoc """
  Centralized process registry that delegates to a configurable backend.
  """
  
  alias Foundation.ProcessRegistry.Server

  @type namespace :: :production | {:test, reference()}
  @type service_name :: atom() | {:agent, atom()} | {:ecosystem_supervisor, atom()}

  # --- Lifecycle ---

  def start_link(opts \\ []) do
    Supervisor.start_link([
      {Registry, [keys: :unique, name: __MODULE__, partitions: System.schedulers_online()]},
      {Server, opts}
    ], strategy: :one_for_one, name: :"#{__MODULE__}.Supervisor")
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  # --- Public API ---

  @spec register(namespace(), service_name(), pid(), map()) :: :ok | {:error, term()}
  def register(namespace, service, pid, metadata \\ %{})
      when is_pid(pid) and is_map(metadata) do
    GenServer.call(Server, {:register, {namespace, service}, pid, metadata})
  end

  def register(_namespace, _service, pid, _metadata) when not is_pid(pid),
    do: {:error, :invalid_pid}

  def register(_namespace, _service, _pid, metadata) when not is_map(metadata),
    do: {:error, :invalid_metadata}

  @spec lookup(namespace(), service_name()) :: {:ok, pid()} | :error
  def lookup(namespace, service) do
    case GenServer.call(Server, {:lookup, {namespace, service}}) do
      {:ok, {pid, _metadata}} -> {:ok, pid}
      {:error, :not_found} -> :error
      {:error, _reason} -> :error
    end
  end

  @spec unregister(namespace(), service_name()) :: :ok
  def unregister(namespace, service) do
    GenServer.call(Server, {:unregister, {namespace, service}})
    Registry.unregister(__MODULE__, {namespace, service})
    :ok
  end

  @spec lookup_with_metadata(namespace(), service_name()) :: {:ok, {pid(), map()}} | :error
  def lookup_with_metadata(namespace, service) do
    case GenServer.call(Server, {:lookup, {namespace, service}}) do
      {:ok, {pid, metadata}} -> {:ok, {pid, metadata}}
      {:error, :not_found} -> :error
      {:error, _reason} -> :error
    end
  end

  @spec update_metadata(namespace(), service_name(), map()) :: :ok | {:error, term()}
  def update_metadata(namespace, service, metadata) when is_map(metadata) do
    GenServer.call(Server, {:update_metadata, {namespace, service}, metadata})
  end

  @spec list_services(namespace()) :: [service_name()]
  def list_services(namespace) do
    case GenServer.call(Server, {:list_all}) do
      {:ok, all_services} ->
        all_services
        |> Enum.filter(fn {{ns, _service}, _pid, _meta} -> ns == namespace end)
        |> Enum.map(fn {{_ns, service}, _pid, _meta} -> service end)
      {:error, _reason} ->
        []
    end
  end

  @spec find_services_by_metadata(namespace(), (map() -> boolean())) :: [{service_name(), pid(), map()}]
  def find_services_by_metadata(namespace, filter_fn) when is_function(filter_fn, 1) do
    case GenServer.call(Server, {:list_all}) do
      {:ok, all_services} ->
        all_services
        |> Enum.filter(fn {{ns, _service}, _pid, meta} -> 
          ns == namespace and filter_fn.(meta)
        end)
        |> Enum.map(fn {{_ns, service}, pid, meta} -> {service, pid, meta} end)
      {:error, _reason} ->
        []
    end
  end

  @spec get_stats() :: {:ok, map()} | {:error, term()}
  def get_stats do
    GenServer.call(Server, {:get_stats})
  end

  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    GenServer.call(Server, {:health_check})
  end

  @spec via_tuple(namespace(), service_name()) :: {:via, Registry, {atom(), {namespace(), service_name()}}}
  def via_tuple(namespace, service) do
    {:via, Registry, {__MODULE__, {namespace, service}}}
  end
end
```

#### Phase 3: Implement OptimizedETS Backend

**Action:** Create `lib/foundation/process_registry/backend/optimized_ets.ex`

```elixir
defmodule Foundation.ProcessRegistry.Backend.OptimizedETS do
  @moduledoc """
  Optimized ETS backend with caching and metadata indexing.
  """
  @behaviour Foundation.ProcessRegistry.Backend

  alias Foundation.ProcessRegistry.Backend.ETS

  @cache_table :process_registry_cache
  @index_table :process_registry_metadata_index
  @cache_ttl 300_000  # 5 minutes

  @impl true
  def init(opts) do
    case ETS.init(opts) do
      {:ok, ets_state} ->
        :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
        :ets.new(@index_table, [:named_table, :public, :bag, read_concurrency: true])
        
        state = %{
          ets_state: ets_state,
          cache_hits: 0,
          cache_misses: 0,
          start_time: System.monotonic_time()
        }
        
        {:ok, state}
      error ->
        error
    end
  end

  @impl true
  def register(state, key, pid, metadata) do
    case ETS.register(state.ets_state, key, pid, metadata) do
      {:ok, new_ets_state} ->
        add_to_metadata_index(key, pid, metadata)
        :ets.delete(@cache_table, key)
        {:ok, %{state | ets_state: new_ets_state}}
      error ->
        error
    end
  end

  @impl true
  def lookup(state, key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, pid, metadata, timestamp}] when is_pid(pid) ->
        current_time = System.monotonic_time(:millisecond)
        if Process.alive?(pid) and (current_time - timestamp) < @cache_ttl do
          {:ok, {pid, metadata}}
        else
          :ets.delete(@cache_table, key)
          cache_miss_lookup(state, key)
        end
      _ ->
        cache_miss_lookup(state, key)
    end
  end

  defp cache_miss_lookup(state, key) do
    case ETS.lookup(state.ets_state, key) do
      {:ok, {pid, metadata}} = result ->
        timestamp = System.monotonic_time(:millisecond)
        :ets.insert(@cache_table, {key, pid, metadata, timestamp})
        result
      error ->
        error
    end
  end

  @impl true
  def unregister(state, key) do
    case ETS.unregister(state.ets_state, key) do
      {:ok, new_ets_state} ->
        :ets.delete(@cache_table, key)
        remove_from_metadata_index(key)
        {:ok, %{state | ets_state: new_ets_state}}
      error ->
        error
    end
  end

  @impl true
  def list_all(state) do
    ETS.list_all(state.ets_state)
  end

  @impl true
  def update_metadata(state, key, metadata) do
    case ETS.update_metadata(state.ets_state, key, metadata) do
      {:ok, new_ets_state} ->
        remove_from_metadata_index(key)
        case ETS.lookup(new_ets_state, key) do
          {:ok, {pid, _}} -> add_to_metadata_index(key, pid, metadata)
          _ -> :ok
        end
        :ets.delete(@cache_table, key)
        {:ok, %{state | ets_state: new_ets_state}}
      error ->
        error
    end
  end

  @impl true
  def health_check(state) do
    case ETS.health_check(state.ets_state) do
      {:ok, ets_health} ->
        cache_info = get_cache_stats(state)
        index_info = get_index_stats()
        
        optimized_health = %{
          backend: :optimized_ets,
          underlying_backend: ets_health,
          cache_stats: cache_info,
          index_stats: index_info
        }
        
        {:ok, optimized_health}
      error ->
        error
    end
  end

  # Private helpers
  defp add_to_metadata_index(key, _pid, metadata) do
    for {meta_key, meta_value} <- metadata do
      :ets.insert(@index_table, {{meta_key, meta_value}, key})
    end
  end

  defp remove_from_metadata_index(key) do
    all_indexes = :ets.tab2list(@index_table)
    for {index_key, stored_key} <- all_indexes do
      if stored_key == key do
        :ets.delete_object(@index_table, {index_key, key})
      end
    end
  end

  defp get_cache_stats(state) do
    total_requests = state.cache_hits + state.cache_misses
    hit_rate = if total_requests > 0, do: state.cache_hits / total_requests, else: 0.0
    
    cache_size = case :ets.info(@cache_table) do
      :undefined -> 0
      info -> Keyword.get(info, :size, 0)
    end
    
    %{cache_size: cache_size, hit_rate: hit_rate}
  end

  defp get_index_stats do
    case :ets.info(@index_table) do
      :undefined -> %{index_size: 0}
      info -> %{index_size: Keyword.get(info, :size, 0)}
    end
  end
end
```

#### Phase 4: Configure and Deploy

**Application config:**
```elixir
children = [
  {Foundation.ProcessRegistry, [
    backend: Foundation.ProcessRegistry.Backend.OptimizedETS,
    backend_opts: []
  ]}
]
```

#### Phase 5: Clean Up

1. **Delete** `lib/foundation/process_registry/optimizations.ex`
2. **Delete** the old hybrid logic from main ProcessRegistry
3. **Update tests** to use the new clean API

### **Result**

- ✅ **Clean architecture** using proper backend abstraction
- ✅ **No legacy bullshit** - fresh, modern implementation
- ✅ **Proper OTP patterns** with GenServer state management
- ✅ **Extensible design** for future backends
- ✅ **Performance optimizations** through OptimizedETS backend

**This is the correct, greenfield implementation** - no migration complexity, no backward compatibility, just clean modern Elixir architecture.