# Phoenix: CRDT Integration and State Management
**Date**: 2025-07-12  
**Version**: 1.0  
**Series**: Distributed Agent System - Part 3 (State Management)

## Executive Summary

This document provides detailed technical specifications for conflict-free replicated data types (CRDT) integration and distributed state management in the Phoenix agent system. Drawing from modern distributed systems research, Delta-CRDT implementations, and production BEAM patterns, Phoenix implements a **multi-tier state architecture** that balances consistency, availability, and partition tolerance based on use case requirements.

**Key Innovation**: Phoenix employs **adaptive state consistency** where different state components can use different consistency models within the same agent, enabling optimal performance and correctness guarantees per data type.

## Table of Contents

1. [CRDT Foundation and Theory](#crdt-foundation-and-theory)
2. [Phoenix State Architecture](#phoenix-state-architecture)
3. [CRDT Implementation Specifications](#crdt-implementation-specifications)
4. [Conflict Resolution Strategies](#conflict-resolution-strategies)
5. [Vector Clock Integration](#vector-clock-integration)
6. [State Replication Protocols](#state-replication-protocols)
7. [Performance Optimization](#performance-optimization)
8. [Consistency Models](#consistency-models)

---

## CRDT Foundation and Theory

### Understanding Conflict-Free Replicated Data Types

```elixir
defmodule Phoenix.CRDT.Theory do
  @moduledoc """
  CRDTs provide mathematical guarantees for distributed state management:
  
  1. **Strong Eventual Consistency**: All replicas converge to same state
  2. **Conflict-Free Merging**: Concurrent updates merge without coordination
  3. **Commutativity**: Operation order doesn't affect final state
  4. **Associativity**: Grouping of operations doesn't matter
  5. **Idempotency**: Duplicate operations don't change state
  """
  
  @type crdt_property :: 
    :strong_eventual_consistency |
    :conflict_free_merging |
    :commutativity |
    :associativity |
    :idempotency
    
  @doc """
  CRDT types and their properties:
  
  State-based CRDTs (CvRDTs):
  - G-Counter: Grow-only counter
  - PN-Counter: Increment/decrement counter
  - G-Set: Grow-only set
  - 2P-Set: Add/remove set
  - OR-Set: Observed-remove set
  - LWW-Register: Last-writer-wins register
  - LWW-Map: Last-writer-wins map
  
  Operation-based CRDTs (CmRDTs):
  - Delta-CRDTs: Efficient state synchronization
  - Pure operation CRDTs: Operation-only synchronization
  """
end
```

### CRDT Mathematical Properties

```elixir
defmodule Phoenix.CRDT.Properties do
  @moduledoc """
  Mathematical foundation for CRDT correctness.
  """
  
  @doc """
  Join semilattice property for state-based CRDTs.
  
  For any CRDT state S, the merge operation ⊔ must satisfy:
  - Commutativity: s1 ⊔ s2 = s2 ⊔ s1
  - Associativity: (s1 ⊔ s2) ⊔ s3 = s1 ⊔ (s2 ⊔ s3)
  - Idempotency: s ⊔ s = s
  """
  def verify_join_semilattice(crdt_module, states) do
    # Verify commutativity
    commutativity = verify_commutativity(crdt_module, states)
    
    # Verify associativity
    associativity = verify_associativity(crdt_module, states)
    
    # Verify idempotency
    idempotency = verify_idempotency(crdt_module, states)
    
    %{
      commutativity: commutativity,
      associativity: associativity,
      idempotency: idempotency,
      valid_semilattice: commutativity and associativity and idempotency
    }
  end
  
  @doc """
  Verify strong eventual consistency property.
  
  All correct replicas that have delivered the same set of updates
  eventually reach the same state.
  """
  def verify_strong_eventual_consistency(crdt_module, update_sequences) do
    # Apply all permutations of updates
    final_states = update_sequences
    |> permutations()
    |> Enum.map(&apply_update_sequence(crdt_module, &1))
    |> Enum.uniq()
    
    # Should converge to single state
    length(final_states) == 1
  end
end
```

---

## Phoenix State Architecture

### Multi-Tier State Design

```elixir
defmodule Phoenix.Agent.State do
  @moduledoc """
  Multi-tier state architecture for Phoenix agents.
  
  State Tiers:
  1. **Local State**: Fast, non-replicated, process-local data
  2. **CRDT State**: Conflict-free replicated data with eventual consistency
  3. **Consensus State**: Strongly consistent data using Raft/Paxos
  4. **Persistent State**: Durable storage with configurable consistency
  5. **Cache State**: Performance optimization with TTL and invalidation
  """
  
  use TypedStruct
  
  typedstruct do
    field :agent_id, String.t(), enforce: true
    field :version, Phoenix.VectorClock.t(), enforce: true
    
    # State tiers with different consistency guarantees
    field :local_state, map(), default: %{}
    field :crdt_state, Phoenix.CRDT.Composite.t(), enforce: true
    field :consensus_state, map(), default: %{}
    field :persistent_state, map(), default: %{}
    field :cache_state, Phoenix.Cache.State.t(), default: Phoenix.Cache.State.new()
    
    # Metadata
    field :replicas, [node()], default: []
    field :consistency_policies, map(), default: %{}
    field :last_modified, DateTime.t(), default: DateTime.utc_now()
  end
  
  @doc """
  Create new agent state with specified consistency requirements.
  """
  def new(agent_id, opts \\ []) do
    crdt_spec = Keyword.get(opts, :crdt_spec, default_crdt_spec())
    replicas = Keyword.get(opts, :replicas, [node()])
    
    %__MODULE__{
      agent_id: agent_id,
      version: Phoenix.VectorClock.new(node()),
      crdt_state: Phoenix.CRDT.Composite.new(crdt_spec),
      replicas: replicas,
      consistency_policies: build_consistency_policies(opts)
    }
  end
  
  @doc """
  Update state with appropriate consistency level.
  """
  def update(state, field, value, opts \\ []) do
    consistency = determine_consistency_level(state, field, opts)
    
    case consistency do
      :local -> update_local_state(state, field, value)
      :crdt -> update_crdt_state(state, field, value, opts)
      :consensus -> update_consensus_state(state, field, value, opts)
      :persistent -> update_persistent_state(state, field, value, opts)
    end
  end
  
  defp default_crdt_spec() do
    %{
      counters: Phoenix.CRDT.PNCounter,
      flags: Phoenix.CRDT.TwoPhaseSet,
      registers: Phoenix.CRDT.LWWRegister,
      maps: Phoenix.CRDT.LWWMap,
      sets: Phoenix.CRDT.ORSet
    }
  end
end
```

### State Consistency Policies

```elixir
defmodule Phoenix.Agent.State.ConsistencyPolicy do
  @moduledoc """
  Define consistency requirements for different state components.
  """
  
  use TypedStruct
  
  typedstruct do
    field :field_name, atom(), enforce: true
    field :consistency_level, consistency_level(), enforce: true
    field :replication_factor, pos_integer(), default: 3
    field :conflict_resolution, conflict_resolution_strategy(), default: :lww
    field :durability, durability_level(), default: :memory
    field :ttl, pos_integer() | nil, default: nil
  end
  
  @type consistency_level :: 
    :local |           # No replication, fastest
    :crdt |            # Eventual consistency, conflict-free
    :consensus |       # Strong consistency, coordination required
    :persistent        # Durable consistency with storage
    
  @type conflict_resolution_strategy ::
    :lww |             # Last-writer-wins
    :vector_clock |    # Causal ordering resolution
    :semantic |        # Domain-specific resolution
    :manual            # Require manual intervention
    
  @type durability_level ::
    :memory |          # In-memory only
    :disk |            # Persisted to disk
    :replicated        # Replicated across nodes
    
  @doc """
  Create consistency policy for agent state field.
  """
  def define_policy(field_name, opts \\ []) do
    %__MODULE__{
      field_name: field_name,
      consistency_level: Keyword.get(opts, :consistency, :crdt),
      replication_factor: Keyword.get(opts, :replication_factor, 3),
      conflict_resolution: Keyword.get(opts, :conflict_resolution, :lww),
      durability: Keyword.get(opts, :durability, :memory),
      ttl: Keyword.get(opts, :ttl)
    }
  end
  
  @doc """
  Standard policies for common agent state patterns.
  """
  def standard_policies() do
    [
      # High-frequency metrics with eventual consistency
      define_policy(:request_count, 
        consistency: :crdt, 
        conflict_resolution: :semantic),
        
      # Configuration with strong consistency
      define_policy(:configuration, 
        consistency: :consensus, 
        durability: :replicated),
        
      # Temporary cache with TTL
      define_policy(:cache_data, 
        consistency: :local, 
        ttl: 300_000),
        
      # Audit log with persistence
      define_policy(:audit_log, 
        consistency: :persistent, 
        durability: :disk)
    ]
  end
end
```

---

## CRDT Implementation Specifications

### Delta-CRDT Foundation

```elixir
defmodule Phoenix.CRDT.Delta do
  @moduledoc """
  Delta-CRDT implementation for efficient state synchronization.
  
  Delta-CRDTs only send incremental changes (deltas) rather than
  full state, significantly reducing network overhead.
  """
  
  @callback new() :: t()
  @callback update(t(), operation()) :: {t(), delta()}
  @callback merge(t(), t()) :: t()
  @callback merge_delta(t(), delta()) :: t()
  @callback delta_interval(t(), version()) :: delta()
  
  @type t :: term()
  @type operation :: term()
  @type delta :: term()
  @type version :: Phoenix.VectorClock.t()
  
  defmacro __using__(opts) do
    quote do
      @behaviour Phoenix.CRDT.Delta
      
      defstruct [
        :state,
        :version,
        :deltas,
        :delta_buffer
      ]
      
      def new() do
        %__MODULE__{
          state: initial_state(),
          version: Phoenix.VectorClock.new(node()),
          deltas: %{},
          delta_buffer: []
        }
      end
      
      # Implement delta buffering for efficient sync
      def buffer_delta(crdt, delta) do
        %{crdt | delta_buffer: [delta | crdt.delta_buffer]}
      end
      
      def flush_deltas(crdt) do
        deltas = Enum.reverse(crdt.delta_buffer)
        {%{crdt | delta_buffer: []}, deltas}
      end
      
      defoverridable [new: 0]
    end
  end
end
```

### G-Counter Implementation

```elixir
defmodule Phoenix.CRDT.GCounter do
  @moduledoc """
  Grow-only counter CRDT implementation.
  
  Features:
  - Increment-only operations
  - Efficient delta synchronization
  - Causal consistency guarantees
  """
  
  use Phoenix.CRDT.Delta
  
  defstruct [:counters, :node_id]
  
  @type t :: %__MODULE__{
    counters: %{node() => non_neg_integer()},
    node_id: node()
  }
  
  def initial_state() do
    %{node() => 0}
  end
  
  def new(node_id \\ node()) do
    %__MODULE__{
      counters: %{node_id => 0},
      node_id: node_id
    }
  end
  
  @doc """
  Increment counter by specified amount.
  """
  def increment(counter, amount \\ 1) when amount >= 0 do
    current_value = Map.get(counter.counters, counter.node_id, 0)
    new_value = current_value + amount
    
    new_counters = Map.put(counter.counters, counter.node_id, new_value)
    delta = %{counter.node_id => amount}
    
    new_counter = %{counter | counters: new_counters}
    {new_counter, delta}
  end
  
  @doc """
  Get current counter value (sum across all nodes).
  """
  def value(counter) do
    counter.counters
    |> Map.values()
    |> Enum.sum()
  end
  
  @doc """
  Merge two G-Counter states.
  """
  def merge(counter1, counter2) do
    all_nodes = MapSet.union(
      MapSet.new(Map.keys(counter1.counters)),
      MapSet.new(Map.keys(counter2.counters))
    )
    
    merged_counters = for node <- all_nodes, into: %{} do
      val1 = Map.get(counter1.counters, node, 0)
      val2 = Map.get(counter2.counters, node, 0)
      {node, max(val1, val2)}
    end
    
    %{counter1 | counters: merged_counters}
  end
  
  @doc """
  Apply delta to counter state.
  """
  def merge_delta(counter, delta) do
    merged_counters = Enum.reduce(delta, counter.counters, fn {node, increment}, acc ->
      current = Map.get(acc, node, 0)
      Map.put(acc, node, current + increment)
    end)
    
    %{counter | counters: merged_counters}
  end
  
  @doc """
  Get delta for synchronization interval.
  """
  def delta_interval(counter, from_version) do
    # Implementation depends on version tracking
    # For simplicity, return recent deltas
    counter.counters
  end
end
```

### PN-Counter Implementation

```elixir
defmodule Phoenix.CRDT.PNCounter do
  @moduledoc """
  Increment/Decrement counter using two G-Counters.
  
  Features:
  - Both increment and decrement operations
  - Composed of two G-Counters (positive and negative)
  - Maintains CRDT properties through composition
  """
  
  use Phoenix.CRDT.Delta
  
  defstruct [:positive, :negative]
  
  @type t :: %__MODULE__{
    positive: Phoenix.CRDT.GCounter.t(),
    negative: Phoenix.CRDT.GCounter.t()
  }
  
  def initial_state() do
    %{positive: Phoenix.CRDT.GCounter.new(), negative: Phoenix.CRDT.GCounter.new()}
  end
  
  def new(node_id \\ node()) do
    %__MODULE__{
      positive: Phoenix.CRDT.GCounter.new(node_id),
      negative: Phoenix.CRDT.GCounter.new(node_id)
    }
  end
  
  @doc """
  Increment counter by specified amount.
  """
  def increment(counter, amount \\ 1) when amount >= 0 do
    {new_positive, delta} = Phoenix.CRDT.GCounter.increment(counter.positive, amount)
    new_counter = %{counter | positive: new_positive}
    {new_counter, {:positive, delta}}
  end
  
  @doc """
  Decrement counter by specified amount.
  """
  def decrement(counter, amount \\ 1) when amount >= 0 do
    {new_negative, delta} = Phoenix.CRDT.GCounter.increment(counter.negative, amount)
    new_counter = %{counter | negative: new_negative}
    {new_counter, {:negative, delta}}
  end
  
  @doc """
  Get current counter value (positive - negative).
  """
  def value(counter) do
    positive_value = Phoenix.CRDT.GCounter.value(counter.positive)
    negative_value = Phoenix.CRDT.GCounter.value(counter.negative)
    positive_value - negative_value
  end
  
  @doc """
  Merge two PN-Counter states.
  """
  def merge(counter1, counter2) do
    %__MODULE__{
      positive: Phoenix.CRDT.GCounter.merge(counter1.positive, counter2.positive),
      negative: Phoenix.CRDT.GCounter.merge(counter1.negative, counter2.negative)
    }
  end
  
  @doc """
  Apply delta to PN-Counter state.
  """
  def merge_delta(counter, {:positive, delta}) do
    new_positive = Phoenix.CRDT.GCounter.merge_delta(counter.positive, delta)
    %{counter | positive: new_positive}
  end
  
  def merge_delta(counter, {:negative, delta}) do
    new_negative = Phoenix.CRDT.GCounter.merge_delta(counter.negative, delta)
    %{counter | negative: new_negative}
  end
end
```

### OR-Set Implementation

```elixir
defmodule Phoenix.CRDT.ORSet do
  @moduledoc """
  Observed-Remove Set CRDT implementation.
  
  Features:
  - Add and remove operations
  - Resolves add-remove conflicts by bias towards add
  - Uses unique tags to distinguish concurrent operations
  """
  
  use Phoenix.CRDT.Delta
  
  defstruct [:elements, :removed, :node_id]
  
  @type element :: term()
  @type tag :: {node(), reference()}
  @type t :: %__MODULE__{
    elements: %{element() => MapSet.t(tag())},
    removed: %{element() => MapSet.t(tag())},
    node_id: node()
  }
  
  def initial_state() do
    %{elements: %{}, removed: %{}, node_id: node()}
  end
  
  def new(node_id \\ node()) do
    %__MODULE__{
      elements: %{},
      removed: %{},
      node_id: node_id
    }
  end
  
  @doc """
  Add element to set with unique tag.
  """
  def add(set, element) do
    tag = {set.node_id, make_ref()}
    current_tags = Map.get(set.elements, element, MapSet.new())
    new_tags = MapSet.put(current_tags, tag)
    
    new_elements = Map.put(set.elements, element, new_tags)
    delta = {:add, element, tag}
    
    new_set = %{set | elements: new_elements}
    {new_set, delta}
  end
  
  @doc """
  Remove element from set (mark all current tags as removed).
  """
  def remove(set, element) do
    current_tags = Map.get(set.elements, element, MapSet.new())
    current_removed = Map.get(set.removed, element, MapSet.new())
    new_removed_tags = MapSet.union(current_removed, current_tags)
    
    new_removed = Map.put(set.removed, element, new_removed_tags)
    delta = {:remove, element, current_tags}
    
    new_set = %{set | removed: new_removed}
    {new_set, delta}
  end
  
  @doc """
  Get current set members (elements with non-removed tags).
  """
  def members(set) do
    set.elements
    |> Enum.filter(fn {element, tags} ->
      removed_tags = Map.get(set.removed, element, MapSet.new())
      not MapSet.equal?(tags, removed_tags) and not MapSet.subset?(tags, removed_tags)
    end)
    |> Enum.map(fn {element, _tags} -> element end)
    |> MapSet.new()
  end
  
  @doc """
  Check if element is in set.
  """
  def member?(set, element) do
    element in members(set)
  end
  
  @doc """
  Merge two OR-Set states.
  """
  def merge(set1, set2) do
    all_elements = MapSet.union(
      MapSet.new(Map.keys(set1.elements)),
      MapSet.new(Map.keys(set2.elements))
    )
    
    merged_elements = for element <- all_elements, into: %{} do
      tags1 = Map.get(set1.elements, element, MapSet.new())
      tags2 = Map.get(set2.elements, element, MapSet.new())
      {element, MapSet.union(tags1, tags2)}
    end
    
    merged_removed = for element <- all_elements, into: %{} do
      removed1 = Map.get(set1.removed, element, MapSet.new())
      removed2 = Map.get(set2.removed, element, MapSet.new())
      {element, MapSet.union(removed1, removed2)}
    end
    
    %{set1 | elements: merged_elements, removed: merged_removed}
  end
  
  @doc """
  Apply delta to OR-Set state.
  """
  def merge_delta(set, {:add, element, tag}) do
    current_tags = Map.get(set.elements, element, MapSet.new())
    new_tags = MapSet.put(current_tags, tag)
    new_elements = Map.put(set.elements, element, new_tags)
    
    %{set | elements: new_elements}
  end
  
  def merge_delta(set, {:remove, element, tags}) do
    current_removed = Map.get(set.removed, element, MapSet.new())
    new_removed_tags = MapSet.union(current_removed, tags)
    new_removed = Map.put(set.removed, element, new_removed_tags)
    
    %{set | removed: new_removed}
  end
end
```

### LWW-Map Implementation

```elixir
defmodule Phoenix.CRDT.LWWMap do
  @moduledoc """
  Last-Writer-Wins Map CRDT implementation.
  
  Features:
  - Map operations with timestamp-based conflict resolution
  - Put and remove operations
  - Configurable bias for concurrent operations
  """
  
  use Phoenix.CRDT.Delta
  
  defstruct [:entries, :tombstones, :node_id, :bias]
  
  @type key :: term()
  @type value :: term()
  @type timestamp :: {integer(), node()}
  @type bias :: :add | :remove
  @type t :: %__MODULE__{
    entries: %{key() => {value(), timestamp()}},
    tombstones: %{key() => timestamp()},
    node_id: node(),
    bias: bias()
  }
  
  def initial_state() do
    %{entries: %{}, tombstones: %{}, node_id: node(), bias: :add}
  end
  
  def new(node_id \\ node(), bias \\ :add) do
    %__MODULE__{
      entries: %{},
      tombstones: %{},
      node_id: node_id,
      bias: bias
    }
  end
  
  @doc """
  Put key-value pair with timestamp.
  """
  def put(map, key, value) do
    timestamp = {System.system_time(:microsecond), map.node_id}
    new_entries = Map.put(map.entries, key, {value, timestamp})
    delta = {:put, key, value, timestamp}
    
    new_map = %{map | entries: new_entries}
    {new_map, delta}
  end
  
  @doc """
  Remove key with timestamp.
  """
  def remove(map, key) do
    timestamp = {System.system_time(:microsecond), map.node_id}
    new_tombstones = Map.put(map.tombstones, key, timestamp)
    delta = {:remove, key, timestamp}
    
    new_map = %{map | tombstones: new_tombstones}
    {new_map, delta}
  end
  
  @doc """
  Get value for key (considering tombstones).
  """
  def get(map, key) do
    case Map.get(map.entries, key) do
      nil -> 
        nil
      {value, entry_timestamp} ->
        case Map.get(map.tombstones, key) do
          nil -> 
            value
          tombstone_timestamp ->
            if timestamp_greater?(entry_timestamp, tombstone_timestamp, map.bias) do
              value
            else
              nil
            end
        end
    end
  end
  
  @doc """
  Get all current entries (excluding tombstoned entries).
  """
  def entries(map) do
    map.entries
    |> Enum.filter(fn {key, {_value, timestamp}} ->
      case Map.get(map.tombstones, key) do
        nil -> true
        tombstone_timestamp -> 
          timestamp_greater?(timestamp, tombstone_timestamp, map.bias)
      end
    end)
    |> Enum.into(%{}, fn {key, {value, _timestamp}} -> {key, value} end)
  end
  
  @doc """
  Merge two LWW-Map states.
  """
  def merge(map1, map2) do
    all_keys = MapSet.union(
      MapSet.new(Map.keys(map1.entries)),
      MapSet.new(Map.keys(map2.entries))
    )
    
    merged_entries = for key <- all_keys, into: %{} do
      entry1 = Map.get(map1.entries, key)
      entry2 = Map.get(map2.entries, key)
      
      case {entry1, entry2} do
        {nil, entry} -> {key, entry}
        {entry, nil} -> {key, entry}
        {{value1, ts1}, {value2, ts2}} ->
          if timestamp_greater?(ts1, ts2, map1.bias) do
            {key, {value1, ts1}}
          else
            {key, {value2, ts2}}
          end
      end
    end
    
    all_tombstone_keys = MapSet.union(
      MapSet.new(Map.keys(map1.tombstones)),
      MapSet.new(Map.keys(map2.tombstones))
    )
    
    merged_tombstones = for key <- all_tombstone_keys, into: %{} do
      ts1 = Map.get(map1.tombstones, key)
      ts2 = Map.get(map2.tombstones, key)
      
      case {ts1, ts2} do
        {nil, ts} -> {key, ts}
        {ts, nil} -> {key, ts}
        {ts1, ts2} ->
          if timestamp_greater?(ts1, ts2, map1.bias) do
            {key, ts1}
          else
            {key, ts2}
          end
      end
    end
    
    %{map1 | entries: merged_entries, tombstones: merged_tombstones}
  end
  
  @doc """
  Apply delta to LWW-Map state.
  """
  def merge_delta(map, {:put, key, value, timestamp}) do
    case Map.get(map.entries, key) do
      nil ->
        new_entries = Map.put(map.entries, key, {value, timestamp})
        %{map | entries: new_entries}
      {_current_value, current_timestamp} ->
        if timestamp_greater?(timestamp, current_timestamp, map.bias) do
          new_entries = Map.put(map.entries, key, {value, timestamp})
          %{map | entries: new_entries}
        else
          map
        end
    end
  end
  
  def merge_delta(map, {:remove, key, timestamp}) do
    case Map.get(map.tombstones, key) do
      nil ->
        new_tombstones = Map.put(map.tombstones, key, timestamp)
        %{map | tombstones: new_tombstones}
      current_timestamp ->
        if timestamp_greater?(timestamp, current_timestamp, map.bias) do
          new_tombstones = Map.put(map.tombstones, key, timestamp)
          %{map | tombstones: new_tombstones}
        else
          map
        end
    end
  end
  
  # Helper function for timestamp comparison with bias
  defp timestamp_greater?({time1, node1}, {time2, node2}, bias) do
    cond do
      time1 > time2 -> true
      time1 < time2 -> false
      time1 == time2 ->
        case bias do
          :add -> node1 >= node2  # Bias towards add operations
          :remove -> node1 <= node2  # Bias towards remove operations
        end
    end
  end
end
```

---

## Conflict Resolution Strategies

### Semantic Conflict Resolution

```elixir
defmodule Phoenix.CRDT.ConflictResolution do
  @moduledoc """
  Advanced conflict resolution strategies for domain-specific CRDTs.
  """
  
  @type resolution_strategy :: 
    :last_writer_wins |
    :first_writer_wins |
    :vector_clock |
    :semantic |
    :manual |
    :custom
    
  @type conflict_context :: %{
    data_type: atom(),
    operation_type: atom(),
    conflicting_values: [term()],
    timestamps: [timestamp()],
    vector_clocks: [Phoenix.VectorClock.t()],
    metadata: map()
  }
  
  @doc """
  Resolve conflicts using specified strategy.
  """
  def resolve_conflict(conflicting_states, strategy, context \\ %{}) do
    case strategy do
      :last_writer_wins -> 
        resolve_lww(conflicting_states)
      :first_writer_wins -> 
        resolve_fww(conflicting_states)
      :vector_clock -> 
        resolve_vector_clock(conflicting_states, context)
      :semantic -> 
        resolve_semantic(conflicting_states, context)
      :manual -> 
        queue_for_manual_resolution(conflicting_states, context)
      {:custom, resolver_fn} when is_function(resolver_fn) ->
        resolver_fn.(conflicting_states, context)
    end
  end
  
  @doc """
  Semantic conflict resolution for specific data types.
  """
  def resolve_semantic(conflicting_states, context) do
    case context.data_type do
      :counter -> resolve_counter_conflict(conflicting_states)
      :set -> resolve_set_conflict(conflicting_states)
      :map -> resolve_map_conflict(conflicting_states, context)
      :list -> resolve_list_conflict(conflicting_states, context)
      :register -> resolve_register_conflict(conflicting_states, context)
      _ -> resolve_lww(conflicting_states)
    end
  end
  
  defp resolve_counter_conflict(states) do
    # For counters, sum all increments
    states
    |> Enum.map(&extract_counter_value/1)
    |> Enum.sum()
  end
  
  defp resolve_set_conflict(states) do
    # For sets, take union of all elements
    states
    |> Enum.map(&extract_set_elements/1)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end
  
  defp resolve_map_conflict(states, context) do
    # For maps, merge with per-key conflict resolution
    all_keys = states
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    
    for key <- all_keys, into: %{} do
      key_values = states
      |> Enum.map(&Map.get(&1, key))
      |> Enum.filter(&(&1 != nil))
      
      resolved_value = case length(key_values) do
        0 -> nil
        1 -> hd(key_values)
        _ -> resolve_key_conflict(key, key_values, context)
      end
      
      {key, resolved_value}
    end
  end
  
  defp resolve_key_conflict(key, values, context) do
    key_strategy = get_key_strategy(key, context)
    resolve_conflict(values, key_strategy, context)
  end
  
  @doc """
  Vector clock based conflict resolution.
  """
  def resolve_vector_clock(conflicting_states, context) do
    vector_clocks = Map.get(context, :vector_clocks, [])
    
    case find_causal_ordering(vector_clocks) do
      {:total_order, ordered_clocks} ->
        # Use causally latest state
        latest_clock = List.last(ordered_clocks)
        find_state_for_clock(conflicting_states, latest_clock)
        
      {:partial_order, concurrent_clocks} ->
        # Fall back to semantic or LWW resolution
        concurrent_states = find_states_for_clocks(conflicting_states, concurrent_clocks)
        resolve_semantic(concurrent_states, context)
        
      {:no_ordering, _} ->
        # All states are concurrent, use semantic resolution
        resolve_semantic(conflicting_states, context)
    end
  end
end
```

### Domain-Specific Resolution

```elixir
defmodule Phoenix.CRDT.DomainResolution do
  @moduledoc """
  Domain-specific conflict resolution for common agent patterns.
  """
  
  @doc """
  Resolve configuration conflicts (bias towards consistency).
  """
  def resolve_configuration_conflict(configs, context) do
    # For configuration, prefer newer values but validate consistency
    latest_config = Enum.max_by(configs, &get_timestamp/1)
    
    case validate_configuration(latest_config, context) do
      {:ok, valid_config} -> valid_config
      {:error, :invalid} -> 
        # Fall back to last known good configuration
        find_last_valid_configuration(configs, context)
    end
  end
  
  @doc """
  Resolve metric conflicts (aggregate values).
  """
  def resolve_metrics_conflict(metrics, context) do
    case context.metric_type do
      :counter -> 
        # Sum all counter values
        Enum.sum(metrics)
      :gauge -> 
        # Use latest gauge value
        List.last(metrics)
      :histogram -> 
        # Merge histogram buckets
        merge_histograms(metrics)
      :set -> 
        # Union of all set elements
        Enum.reduce(metrics, MapSet.new(), &MapSet.union/2)
    end
  end
  
  @doc """
  Resolve state machine conflicts (ensure valid transitions).
  """
  def resolve_state_machine_conflict(states, context) do
    state_machine = Map.get(context, :state_machine)
    current_state = Map.get(context, :current_state)
    
    # Find valid transitions from current state
    valid_transitions = find_valid_transitions(state_machine, current_state, states)
    
    case valid_transitions do
      [] -> 
        # No valid transitions, keep current state
        current_state
      [single_transition] -> 
        # Single valid transition
        single_transition
      multiple_transitions ->
        # Multiple valid transitions, use priority or timestamp
        resolve_transition_conflict(multiple_transitions, context)
    end
  end
  
  @doc """
  Resolve resource allocation conflicts (fair distribution).
  """
  def resolve_resource_conflict(allocations, context) do
    total_requested = Enum.sum(allocations)
    available_resources = Map.get(context, :available_resources, total_requested)
    
    if total_requested <= available_resources do
      # All allocations can be satisfied
      allocations
    else
      # Need to scale down proportionally
      scale_factor = available_resources / total_requested
      Enum.map(allocations, &(&1 * scale_factor))
    end
  end
end
```

---

## Vector Clock Integration

### Vector Clock Implementation

```elixir
defmodule Phoenix.VectorClock do
  @moduledoc """
  Vector clock implementation for causal consistency tracking.
  
  Features:
  - Efficient encoding for network transmission
  - Automatic pruning of old entries
  - Integration with CRDT operations
  - Conflict detection and causal ordering
  """
  
  use TypedStruct
  
  typedstruct do
    field :clocks, %{node() => non_neg_integer()}, default: %{}
    field :node_id, node(), enforce: true
  end
  
  @type relation :: :equal | :less | :greater | :concurrent
  
  @doc """
  Create new vector clock for specified node.
  """
  def new(node_id) do
    %__MODULE__{
      clocks: %{node_id => 0},
      node_id: node_id
    }
  end
  
  @doc """
  Increment logical time for local node.
  """
  def tick(vector_clock) do
    current_time = Map.get(vector_clock.clocks, vector_clock.node_id, 0)
    new_clocks = Map.put(vector_clock.clocks, vector_clock.node_id, current_time + 1)
    
    %{vector_clock | clocks: new_clocks}
  end
  
  @doc """
  Update vector clock when receiving message.
  """
  def update(local_clock, remote_clock) do
    # Merge clocks taking maximum of each component
    all_nodes = MapSet.union(
      MapSet.new(Map.keys(local_clock.clocks)),
      MapSet.new(Map.keys(remote_clock.clocks))
    )
    
    merged_clocks = for node <- all_nodes, into: %{} do
      local_time = Map.get(local_clock.clocks, node, 0)
      remote_time = Map.get(remote_clock.clocks, node, 0)
      {node, max(local_time, remote_time)}
    end
    
    # Increment local node time
    local_time = Map.get(merged_clocks, local_clock.node_id, 0)
    final_clocks = Map.put(merged_clocks, local_clock.node_id, local_time + 1)
    
    %{local_clock | clocks: final_clocks}
  end
  
  @doc """
  Compare two vector clocks for causal ordering.
  """
  def compare(clock_a, clock_b) do
    all_nodes = MapSet.union(
      MapSet.new(Map.keys(clock_a.clocks)),
      MapSet.new(Map.keys(clock_b.clocks))
    )
    
    comparisons = Enum.map(all_nodes, fn node ->
      time_a = Map.get(clock_a.clocks, node, 0)
      time_b = Map.get(clock_b.clocks, node, 0)
      
      cond do
        time_a < time_b -> :less
        time_a > time_b -> :greater
        true -> :equal
      end
    end)
    
    determine_relationship(comparisons)
  end
  
  defp determine_relationship(comparisons) do
    unique_comparisons = Enum.uniq(comparisons)
    
    case unique_comparisons do
      [:equal] -> :equal
      [:less] -> :less
      [:greater] -> :greater
      [:equal, :less] -> :less
      [:equal, :greater] -> :greater
      _ -> :concurrent
    end
  end
  
  @doc """
  Check if one clock happened before another.
  """
  def happens_before?(clock_a, clock_b) do
    compare(clock_a, clock_b) == :less
  end
  
  @doc """
  Check if two clocks are concurrent.
  """
  def concurrent?(clock_a, clock_b) do
    compare(clock_a, clock_b) == :concurrent
  end
  
  @doc """
  Encode vector clock for efficient network transmission.
  """
  def encode(vector_clock) do
    # Use binary encoding for efficiency
    sorted_entries = vector_clock.clocks
    |> Enum.sort_by(fn {node, _time} -> node end)
    
    :erlang.term_to_binary(sorted_entries, [:compressed])
  end
  
  @doc """
  Decode vector clock from binary representation.
  """
  def decode(binary_data, node_id) do
    clocks = :erlang.binary_to_term(binary_data)
    |> Enum.into(%{})
    
    %__MODULE__{clocks: clocks, node_id: node_id}
  end
  
  @doc """
  Prune old entries from vector clock (garbage collection).
  """
  def prune(vector_clock, keep_nodes) do
    pruned_clocks = vector_clock.clocks
    |> Enum.filter(fn {node, _time} -> node in keep_nodes end)
    |> Enum.into(%{})
    
    %{vector_clock | clocks: pruned_clocks}
  end
end
```

### Causal Consistency Manager

```elixir
defmodule Phoenix.CRDT.CausalConsistency do
  @moduledoc """
  Manages causal consistency across CRDT operations.
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :current_clock,
    :pending_operations,
    :delivered_operations,
    :causal_dependencies
  ]
  
  @doc """
  Start causal consistency manager.
  """
  def start_link(opts \\ []) do
    node_id = Keyword.get(opts, :node_id, node())
    
    GenServer.start_link(__MODULE__, node_id, name: __MODULE__)
  end
  
  def init(node_id) do
    state = %__MODULE__{
      node_id: node_id,
      current_clock: Phoenix.VectorClock.new(node_id),
      pending_operations: [],
      delivered_operations: MapSet.new(),
      causal_dependencies: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Process CRDT operation with causal ordering.
  """
  def handle_operation(operation, vector_clock) do
    GenServer.call(__MODULE__, {:handle_operation, operation, vector_clock})
  end
  
  @doc """
  Get current vector clock.
  """
  def current_clock() do
    GenServer.call(__MODULE__, :current_clock)
  end
  
  def handle_call({:handle_operation, operation, remote_clock}, _from, state) do
    # Check if operation can be delivered immediately
    case can_deliver?(operation, remote_clock, state) do
      true ->
        # Deliver operation and update clock
        new_state = deliver_operation(operation, remote_clock, state)
        {:reply, :delivered, new_state}
        
      false ->
        # Queue operation for later delivery
        new_state = queue_operation(operation, remote_clock, state)
        {:reply, :queued, new_state}
    end
  end
  
  def handle_call(:current_clock, _from, state) do
    {:reply, state.current_clock, state}
  end
  
  defp can_deliver?(operation, remote_clock, state) do
    # Check if all causal dependencies are satisfied
    dependencies = get_dependencies(operation)
    
    Enum.all?(dependencies, fn dep_id ->
      MapSet.member?(state.delivered_operations, dep_id)
    end)
  end
  
  defp deliver_operation(operation, remote_clock, state) do
    # Update vector clock
    new_clock = Phoenix.VectorClock.update(state.current_clock, remote_clock)
    
    # Mark operation as delivered
    operation_id = get_operation_id(operation)
    new_delivered = MapSet.put(state.delivered_operations, operation_id)
    
    # Check if any pending operations can now be delivered
    {deliverable_ops, remaining_ops} = partition_deliverable(state.pending_operations, state)
    
    # Process deliverable operations
    final_state = Enum.reduce(deliverable_ops, state, fn {op, clock}, acc ->
      deliver_operation(op, clock, acc)
    end)
    
    %{final_state | 
      current_clock: new_clock,
      delivered_operations: new_delivered,
      pending_operations: remaining_ops
    }
  end
  
  defp queue_operation(operation, remote_clock, state) do
    new_pending = [{operation, remote_clock} | state.pending_operations]
    %{state | pending_operations: new_pending}
  end
  
  defp partition_deliverable(pending_operations, state) do
    Enum.split_with(pending_operations, fn {operation, _clock} ->
      can_deliver?(operation, nil, state)
    end)
  end
end
```

---

## State Replication Protocols

### Delta Synchronization Protocol

```elixir
defmodule Phoenix.CRDT.DeltaSync do
  @moduledoc """
  Efficient delta synchronization protocol for CRDT state.
  
  Features:
  - Incremental state synchronization
  - Bandwidth optimization through delta compression
  - Adaptive synchronization intervals
  - Conflict-free merge operations
  """
  
  use GenServer
  
  defstruct [
    :agent_id,
    :local_state,
    :peer_states,
    :delta_buffer,
    :sync_intervals,
    :compression_enabled
  ]
  
  @default_sync_interval 5_000  # 5 seconds
  @max_delta_buffer_size 1000
  
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    initial_state = Keyword.get(opts, :initial_state)
    
    state = %__MODULE__{
      agent_id: agent_id,
      local_state: initial_state,
      peer_states: %{},
      delta_buffer: [],
      sync_intervals: %{},
      compression_enabled: Keyword.get(opts, :compression, true)
    }
    
    # Schedule periodic synchronization
    schedule_sync()
    
    {:ok, state}
  end
  
  @doc """
  Apply local CRDT operation and buffer delta.
  """
  def apply_operation(agent_id, operation) do
    GenServer.call(via_tuple(agent_id), {:apply_operation, operation})
  end
  
  @doc """
  Receive and apply delta from peer.
  """
  def receive_delta(agent_id, peer_node, delta) do
    GenServer.cast(via_tuple(agent_id), {:receive_delta, peer_node, delta})
  end
  
  @doc """
  Request full state synchronization.
  """
  def request_full_sync(agent_id, peer_node) do
    GenServer.call(via_tuple(agent_id), {:request_full_sync, peer_node})
  end
  
  def handle_call({:apply_operation, operation}, _from, state) do
    # Apply operation to local state
    {new_local_state, delta} = apply_crdt_operation(state.local_state, operation)
    
    # Buffer delta for synchronization
    new_delta_buffer = [delta | state.delta_buffer]
    |> Enum.take(@max_delta_buffer_size)
    
    new_state = %{state | 
      local_state: new_local_state,
      delta_buffer: new_delta_buffer
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:request_full_sync, peer_node}, _from, state) do
    # Send full state to peer
    compressed_state = maybe_compress(state.local_state, state.compression_enabled)
    
    Phoenix.CRDT.DeltaSync.receive_full_state(
      peer_node, 
      state.agent_id, 
      compressed_state
    )
    
    {:reply, :ok, state}
  end
  
  def handle_cast({:receive_delta, peer_node, delta}, state) do
    # Decompress delta if needed
    decompressed_delta = maybe_decompress(delta, state.compression_enabled)
    
    # Apply delta to local state
    new_local_state = merge_delta(state.local_state, decompressed_delta)
    
    # Update peer state tracking
    new_peer_states = update_peer_state(state.peer_states, peer_node, decompressed_delta)
    
    new_state = %{state | 
      local_state: new_local_state,
      peer_states: new_peer_states
    }
    
    {:noreply, new_state}
  end
  
  def handle_cast({:receive_full_state, peer_node, full_state}, state) do
    # Decompress full state if needed
    decompressed_state = maybe_decompress(full_state, state.compression_enabled)
    
    # Merge with local state
    new_local_state = merge_states(state.local_state, decompressed_state)
    
    # Update peer state tracking
    new_peer_states = Map.put(state.peer_states, peer_node, decompressed_state)
    
    new_state = %{state | 
      local_state: new_local_state,
      peer_states: new_peer_states
    }
    
    {:noreply, new_state}
  end
  
  def handle_info(:sync_deltas, state) do
    # Send buffered deltas to all peers
    if not Enum.empty?(state.delta_buffer) do
      combined_delta = combine_deltas(state.delta_buffer)
      compressed_delta = maybe_compress(combined_delta, state.compression_enabled)
      
      broadcast_delta_to_peers(state.agent_id, compressed_delta)
      
      new_state = %{state | delta_buffer: []}
      schedule_sync()
      
      {:noreply, new_state}
    else
      schedule_sync()
      {:noreply, state}
    end
  end
  
  defp schedule_sync() do
    Process.send_after(self(), :sync_deltas, @default_sync_interval)
  end
  
  defp broadcast_delta_to_peers(agent_id, delta) do
    # Get list of peer nodes for this agent
    peer_nodes = Phoenix.Cluster.Registry.get_replica_nodes(agent_id)
    
    Enum.each(peer_nodes, fn peer_node ->
      if peer_node != node() do
        Phoenix.CRDT.DeltaSync.receive_delta(peer_node, agent_id, node(), delta)
      end
    end)
  end
  
  defp maybe_compress(data, true) do
    :zlib.compress(:erlang.term_to_binary(data))
  end
  
  defp maybe_compress(data, false) do
    :erlang.term_to_binary(data)
  end
  
  defp maybe_decompress(data, true) do
    :erlang.binary_to_term(:zlib.uncompress(data))
  end
  
  defp maybe_decompress(data, false) do
    :erlang.binary_to_term(data)
  end
  
  defp via_tuple(agent_id) do
    {:via, Registry, {Phoenix.CRDT.DeltaSync.Registry, agent_id}}
  end
end
```

### Anti-Entropy Protocol

```elixir
defmodule Phoenix.CRDT.AntiEntropy do
  @moduledoc """
  Anti-entropy protocol for ensuring eventual consistency.
  
  Features:
  - Periodic state reconciliation
  - Merkle tree-based difference detection
  - Adaptive synchronization based on divergence
  - Network-efficient synchronization
  """
  
  use GenServer
  
  defstruct [
    :agent_id,
    :local_merkle_tree,
    :peer_merkle_trees,
    :sync_schedule,
    :divergence_threshold
  ]
  
  @default_anti_entropy_interval 30_000  # 30 seconds
  @divergence_threshold 0.1  # 10% state divergence triggers sync
  
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    state = %__MODULE__{
      agent_id: agent_id,
      local_merkle_tree: build_merkle_tree(get_local_state(agent_id)),
      peer_merkle_trees: %{},
      sync_schedule: %{},
      divergence_threshold: Keyword.get(opts, :divergence_threshold, @divergence_threshold)
    }
    
    # Schedule anti-entropy process
    schedule_anti_entropy()
    
    {:ok, state}
  end
  
  @doc """
  Trigger anti-entropy synchronization with specific peer.
  """
  def sync_with_peer(agent_id, peer_node) do
    GenServer.cast(via_tuple(agent_id), {:sync_with_peer, peer_node})
  end
  
  @doc """
  Update local merkle tree after state change.
  """
  def update_merkle_tree(agent_id) do
    GenServer.cast(via_tuple(agent_id), :update_merkle_tree)
  end
  
  def handle_cast({:sync_with_peer, peer_node}, state) do
    # Get peer's merkle tree
    case request_merkle_tree(peer_node, state.agent_id) do
      {:ok, peer_merkle_tree} ->
        # Compare merkle trees to find differences
        differences = compare_merkle_trees(state.local_merkle_tree, peer_merkle_tree)
        
        if significant_divergence?(differences, state.divergence_threshold) do
          # Perform targeted synchronization
          perform_targeted_sync(peer_node, differences, state)
        end
        
        # Update peer merkle tree cache
        new_peer_trees = Map.put(state.peer_merkle_trees, peer_node, peer_merkle_tree)
        {:noreply, %{state | peer_merkle_trees: new_peer_trees}}
        
      {:error, _reason} ->
        # Peer unavailable, skip this round
        {:noreply, state}
    end
  end
  
  def handle_cast(:update_merkle_tree, state) do
    new_merkle_tree = build_merkle_tree(get_local_state(state.agent_id))
    {:noreply, %{state | local_merkle_tree: new_merkle_tree}}
  end
  
  def handle_info(:anti_entropy, state) do
    # Perform anti-entropy with all replica nodes
    replica_nodes = Phoenix.Cluster.Registry.get_replica_nodes(state.agent_id)
    
    Enum.each(replica_nodes, fn peer_node ->
      if peer_node != node() do
        sync_with_peer(state.agent_id, peer_node)
      end
    end)
    
    schedule_anti_entropy()
    {:noreply, state}
  end
  
  defp schedule_anti_entropy() do
    Process.send_after(self(), :anti_entropy, @default_anti_entropy_interval)
  end
  
  defp build_merkle_tree(state) do
    # Build merkle tree from CRDT state
    state_chunks = partition_state(state)
    
    Phoenix.MerkleTree.build(state_chunks, &:crypto.hash(:sha256, &1))
  end
  
  defp compare_merkle_trees(local_tree, peer_tree) do
    # Find differing nodes in merkle trees
    Phoenix.MerkleTree.diff(local_tree, peer_tree)
  end
  
  defp significant_divergence?(differences, threshold) do
    # Determine if differences exceed threshold
    divergence_ratio = length(differences.differing_nodes) / differences.total_nodes
    divergence_ratio > threshold
  end
  
  defp perform_targeted_sync(peer_node, differences, state) do
    # Request only the differing state chunks
    differing_chunks = differences.differing_nodes
    
    case request_state_chunks(peer_node, state.agent_id, differing_chunks) do
      {:ok, peer_chunks} ->
        # Merge peer chunks with local state
        merge_state_chunks(state.agent_id, peer_chunks)
        
      {:error, _reason} ->
        # Fall back to full state synchronization
        Phoenix.CRDT.DeltaSync.request_full_sync(state.agent_id, peer_node)
    end
  end
  
  defp request_merkle_tree(peer_node, agent_id) do
    case :rpc.call(peer_node, Phoenix.CRDT.AntiEntropy, :get_merkle_tree, [agent_id]) do
      {:badrpc, reason} -> {:error, reason}
      merkle_tree -> {:ok, merkle_tree}
    end
  end
  
  defp via_tuple(agent_id) do
    {:via, Registry, {Phoenix.CRDT.AntiEntropy.Registry, agent_id}}
  end
end
```

---

## Performance Optimization

### CRDT Performance Tuning

```elixir
defmodule Phoenix.CRDT.Performance do
  @moduledoc """
  Performance optimization strategies for CRDT operations.
  """
  
  @doc """
  Optimize CRDT state representation for memory efficiency.
  """
  def optimize_state_representation(crdt_state) do
    case crdt_state do
      %Phoenix.CRDT.GCounter{} = counter ->
        optimize_counter_representation(counter)
        
      %Phoenix.CRDT.ORSet{} = set ->
        optimize_set_representation(set)
        
      %Phoenix.CRDT.LWWMap{} = map ->
        optimize_map_representation(map)
        
      _ ->
        crdt_state
    end
  end
  
  defp optimize_counter_representation(counter) do
    # Prune zero entries and compact representation
    non_zero_counters = counter.counters
    |> Enum.filter(fn {_node, count} -> count > 0 end)
    |> Enum.into(%{})
    
    %{counter | counters: non_zero_counters}
  end
  
  defp optimize_set_representation(set) do
    # Remove tombstones for elements with no live tags
    optimized_elements = set.elements
    |> Enum.filter(fn {element, tags} ->
      removed_tags = Map.get(set.removed, element, MapSet.new())
      not MapSet.subset?(tags, removed_tags)
    end)
    |> Enum.into(%{})
    
    # Remove unnecessary tombstone entries
    optimized_removed = set.removed
    |> Enum.filter(fn {element, _} -> Map.has_key?(optimized_elements, element) end)
    |> Enum.into(%{})
    
    %{set | elements: optimized_elements, removed: optimized_removed}
  end
  
  defp optimize_map_representation(map) do
    # Remove old tombstone entries that are no longer needed
    current_time = System.system_time(:microsecond)
    tombstone_ttl = 24 * 60 * 60 * 1_000_000  # 24 hours in microseconds
    
    optimized_tombstones = map.tombstones
    |> Enum.filter(fn {_key, {timestamp, _node}} ->
      current_time - timestamp < tombstone_ttl
    end)
    |> Enum.into(%{})
    
    %{map | tombstones: optimized_tombstones}
  end
  
  @doc """
  Batch CRDT operations for improved performance.
  """
  def batch_operations(operations, batch_size \\ 100) do
    operations
    |> Enum.chunk_every(batch_size)
    |> Enum.map(&apply_batch/1)
  end
  
  defp apply_batch(operation_batch) do
    # Combine operations where possible
    combined_operations = combine_compatible_operations(operation_batch)
    
    # Apply combined operations
    Enum.map(combined_operations, &apply_operation/1)
  end
  
  defp combine_compatible_operations(operations) do
    # Group operations by type and target
    operations
    |> Enum.group_by(&get_operation_key/1)
    |> Enum.map(fn {_key, ops} -> combine_operation_group(ops) end)
  end
  
  @doc """
  Cache frequently accessed CRDT values.
  """
  def cache_computed_values(crdt_state, cache_strategy \\ :lru) do
    case cache_strategy do
      :lru -> implement_lru_cache(crdt_state)
      :time_based -> implement_time_based_cache(crdt_state)
      :size_based -> implement_size_based_cache(crdt_state)
    end
  end
  
  defp implement_lru_cache(crdt_state) do
    # Implement LRU cache for computed values
    cache_size = 1000
    cache = :ets.new(:crdt_cache, [:lru, :public])
    
    # Cache frequently computed values
    cached_values = %{
      member_count: compute_member_count(crdt_state),
      total_value: compute_total_value(crdt_state),
      state_hash: compute_state_hash(crdt_state)
    }
    
    Enum.each(cached_values, fn {key, value} ->
      :ets.insert(cache, {key, value, System.monotonic_time()})
    end)
    
    {crdt_state, cache}
  end
end
```

### Compression and Serialization

```elixir
defmodule Phoenix.CRDT.Compression do
  @moduledoc """
  Compression strategies for CRDT state and delta synchronization.
  """
  
  @type compression_algorithm :: :zlib | :lz4 | :snappy | :none
  
  @doc """
  Compress CRDT state using specified algorithm.
  """
  def compress_state(state, algorithm \\ :zlib) do
    binary_state = :erlang.term_to_binary(state, [:compressed])
    
    case algorithm do
      :zlib -> {:zlib, :zlib.compress(binary_state)}
      :lz4 -> {:lz4, compress_lz4(binary_state)}
      :snappy -> {:snappy, compress_snappy(binary_state)}
      :none -> {:none, binary_state}
    end
  end
  
  @doc """
  Decompress CRDT state.
  """
  def decompress_state({algorithm, compressed_data}) do
    binary_state = case algorithm do
      :zlib -> :zlib.uncompress(compressed_data)
      :lz4 -> decompress_lz4(compressed_data)
      :snappy -> decompress_snappy(compressed_data)
      :none -> compressed_data
    end
    
    :erlang.binary_to_term(binary_state)
  end
  
  @doc """
  Select optimal compression algorithm based on state characteristics.
  """
  def select_compression_algorithm(state) do
    state_size = byte_size(:erlang.term_to_binary(state))
    state_type = detect_state_type(state)
    
    case {state_size, state_type} do
      {size, _} when size < 1000 -> :none  # Small states don't benefit from compression
      {_, :counter} -> :zlib  # Counters compress well with zlib
      {_, :set} -> :lz4  # Sets benefit from fast compression
      {_, :map} -> :snappy  # Maps work well with snappy
      _ -> :zlib  # Default to zlib
    end
  end
  
  @doc """
  Delta compression for incremental synchronization.
  """
  def compress_delta(delta, previous_deltas \\ []) do
    # Use delta compression by finding similarities with previous deltas
    reference_delta = find_best_reference(delta, previous_deltas)
    
    case reference_delta do
      nil -> 
        # No reference, compress independently
        compress_state(delta)
        
      ref_delta ->
        # Compress against reference
        diff = compute_delta_diff(delta, ref_delta)
        compress_state(diff)
    end
  end
  
  defp find_best_reference(delta, previous_deltas) do
    # Find previous delta with highest similarity
    previous_deltas
    |> Enum.max_by(&compute_similarity(delta, &1), fn -> nil end)
  end
  
  defp compute_similarity(delta1, delta2) do
    # Simple similarity metric based on shared keys/structure
    keys1 = extract_keys(delta1) |> MapSet.new()
    keys2 = extract_keys(delta2) |> MapSet.new()
    
    intersection_size = MapSet.intersection(keys1, keys2) |> MapSet.size()
    union_size = MapSet.union(keys1, keys2) |> MapSet.size()
    
    if union_size > 0 do
      intersection_size / union_size
    else
      0.0
    end
  end
  
  # Placeholder implementations for external compression libraries
  defp compress_lz4(data), do: data  # Would use :lz4 library
  defp decompress_lz4(data), do: data
  
  defp compress_snappy(data), do: data  # Would use :snappy library
  defp decompress_snappy(data), do: data
end
```

---

## Consistency Models

### Eventual Consistency Implementation

```elixir
defmodule Phoenix.CRDT.EventualConsistency do
  @moduledoc """
  Eventual consistency model implementation for CRDT operations.
  
  Guarantees:
  - All replicas eventually converge to same state
  - No coordination required for updates
  - High availability during network partitions
  - Monotonic read consistency
  """
  
  use GenServer
  
  defstruct [
    :agent_id,
    :local_replica,
    :remote_replicas,
    :convergence_detector,
    :update_log
  ]
  
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    initial_state = Keyword.get(opts, :initial_state)
    
    state = %__MODULE__{
      agent_id: agent_id,
      local_replica: initial_state,
      remote_replicas: %{},
      convergence_detector: Phoenix.CRDT.ConvergenceDetector.new(),
      update_log: []
    }
    
    {:ok, state}
  end
  
  @doc """
  Apply update with eventual consistency.
  """
  def apply_update(agent_id, update_operation) do
    GenServer.call(via_tuple(agent_id), {:apply_update, update_operation})
  end
  
  @doc """
  Read current state (monotonic read consistency).
  """
  def read_state(agent_id) do
    GenServer.call(via_tuple(agent_id), :read_state)
  end
  
  @doc """
  Check convergence status with replicas.
  """
  def convergence_status(agent_id) do
    GenServer.call(via_tuple(agent_id), :convergence_status)
  end
  
  def handle_call({:apply_update, update_operation}, _from, state) do
    # Apply update to local replica immediately
    {new_local_replica, delta} = apply_crdt_update(state.local_replica, update_operation)
    
    # Log update for convergence tracking
    update_entry = %{
      operation: update_operation,
      delta: delta,
      timestamp: System.system_time(:microsecond),
      vector_clock: Phoenix.VectorClock.tick(get_vector_clock(state))
    }
    
    new_update_log = [update_entry | state.update_log]
    |> Enum.take(1000)  # Keep last 1000 updates
    
    # Propagate delta to replicas asynchronously
    propagate_delta_async(state.agent_id, delta)
    
    new_state = %{state | 
      local_replica: new_local_replica,
      update_log: new_update_log
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:read_state, _from, state) do
    # Return current local state (monotonic read consistency)
    {:reply, {:ok, state.local_replica}, state}
  end
  
  def handle_call(:convergence_status, _from, state) do
    # Check convergence with all known replicas
    convergence_info = check_convergence(state)
    {:reply, convergence_info, state}
  end
  
  defp propagate_delta_async(agent_id, delta) do
    # Get replica nodes
    replica_nodes = Phoenix.Cluster.Registry.get_replica_nodes(agent_id)
    
    # Send delta to each replica asynchronously
    Enum.each(replica_nodes, fn node ->
      if node != node() do
        Task.start(fn ->
          Phoenix.CRDT.EventualConsistency.receive_delta(node, agent_id, delta)
        end)
      end
    end)
  end
  
  defp check_convergence(state) do
    # Compare local state hash with known replica hashes
    local_hash = compute_state_hash(state.local_replica)
    
    replica_hashes = state.remote_replicas
    |> Enum.map(fn {node, replica_state} -> 
      {node, compute_state_hash(replica_state)}
    end)
    |> Enum.into(%{})
    
    converged_nodes = replica_hashes
    |> Enum.filter(fn {_node, hash} -> hash == local_hash end)
    |> Enum.map(fn {node, _hash} -> node end)
    
    diverged_nodes = replica_hashes
    |> Enum.filter(fn {_node, hash} -> hash != local_hash end)
    |> Enum.map(fn {node, _hash} -> node end)
    
    %{
      local_hash: local_hash,
      converged_nodes: converged_nodes,
      diverged_nodes: diverged_nodes,
      convergence_ratio: length(converged_nodes) / (length(converged_nodes) + length(diverged_nodes))
    }
  end
  
  defp via_tuple(agent_id) do
    {:via, Registry, {Phoenix.CRDT.EventualConsistency.Registry, agent_id}}
  end
end
```

### Strong Consistency Implementation

```elixir
defmodule Phoenix.CRDT.StrongConsistency do
  @moduledoc """
  Strong consistency model for critical CRDT operations.
  
  Uses consensus protocols (Raft/Multi-Paxos) for operations requiring
  linearizability and immediate consistency across replicas.
  """
  
  use GenServer
  
  defstruct [
    :agent_id,
    :consensus_group,
    :local_state,
    :committed_operations,
    :pending_operations
  ]
  
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(agent_id))
  end
  
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    consensus_group = Keyword.get(opts, :consensus_group, default_consensus_group(agent_id))
    
    state = %__MODULE__{
      agent_id: agent_id,
      consensus_group: consensus_group,
      local_state: Keyword.get(opts, :initial_state),
      committed_operations: [],
      pending_operations: %{}
    }
    
    # Join consensus group
    Phoenix.Consensus.Raft.join_group(consensus_group, self())
    
    {:ok, state}
  end
  
  @doc """
  Apply update with strong consistency (requires consensus).
  """
  def apply_update_strong(agent_id, update_operation, timeout \\ 5000) do
    GenServer.call(via_tuple(agent_id), {:apply_update_strong, update_operation}, timeout)
  end
  
  @doc """
  Read state with linearizability guarantee.
  """
  def read_state_strong(agent_id, timeout \\ 5000) do
    GenServer.call(via_tuple(agent_id), :read_state_strong, timeout)
  end
  
  def handle_call({:apply_update_strong, update_operation}, from, state) do
    # Propose operation to consensus group
    operation_id = generate_operation_id()
    
    case Phoenix.Consensus.Raft.propose(
      state.consensus_group, 
      {:crdt_update, operation_id, update_operation}
    ) do
      {:ok, proposal_ref} ->
        # Store pending operation
        new_pending = Map.put(state.pending_operations, proposal_ref, {from, update_operation})
        {:noreply, %{state | pending_operations: new_pending}}
        
      {:error, :not_leader} ->
        # Redirect to leader
        case Phoenix.Consensus.Raft.get_leader(state.consensus_group) do
          {:ok, leader_node} ->
            {:reply, {:redirect, leader_node}, state}
          {:error, :no_leader} ->
            {:reply, {:error, :no_leader}, state}
        end
        
      error ->
        {:reply, error, state}
    end
  end
  
  def handle_call(:read_state_strong, from, state) do
    # Ensure we're reading from current leader
    case Phoenix.Consensus.Raft.ensure_leadership(state.consensus_group) do
      :ok ->
        {:reply, {:ok, state.local_state}, state}
      {:error, :not_leader} ->
        case Phoenix.Consensus.Raft.get_leader(state.consensus_group) do
          {:ok, leader_node} ->
            {:reply, {:redirect, leader_node}, state}
          error ->
            {:reply, error, state}
        end
    end
  end
  
  def handle_info({:consensus_commit, proposal_ref, {:crdt_update, operation_id, update_operation}}, state) do
    # Operation committed by consensus
    case Map.pop(state.pending_operations, proposal_ref) do
      {{from, _operation}, new_pending} ->
        # Apply operation to local state
        {new_local_state, _delta} = apply_crdt_update(state.local_state, update_operation)
        
        # Log committed operation
        new_committed = [operation_id | state.committed_operations]
        |> Enum.take(1000)  # Keep last 1000 operations
        
        # Reply to caller
        GenServer.reply(from, :ok)
        
        new_state = %{state | 
          local_state: new_local_state,
          committed_operations: new_committed,
          pending_operations: new_pending
        }
        
        {:noreply, new_state}
        
      {nil, _} ->
        # Operation committed by other replica
        {new_local_state, _delta} = apply_crdt_update(state.local_state, update_operation)
        
        new_committed = [operation_id | state.committed_operations]
        |> Enum.take(1000)
        
        new_state = %{state | 
          local_state: new_local_state,
          committed_operations: new_committed
        }
        
        {:noreply, new_state}
    end
  end
  
  def handle_info({:consensus_abort, proposal_ref, _reason}, state) do
    # Operation aborted by consensus
    case Map.pop(state.pending_operations, proposal_ref) do
      {{from, _operation}, new_pending} ->
        GenServer.reply(from, {:error, :consensus_abort})
        {:noreply, %{state | pending_operations: new_pending}}
        
      {nil, _} ->
        {:noreply, state}
    end
  end
  
  defp default_consensus_group(agent_id) do
    # Create consensus group name based on agent ID
    "crdt_consensus_#{agent_id}"
  end
  
  defp generate_operation_id() do
    {System.system_time(:microsecond), node(), make_ref()}
  end
  
  defp via_tuple(agent_id) do
    {:via, Registry, {Phoenix.CRDT.StrongConsistency.Registry, agent_id}}
  end
end
```

---

## Summary and Integration Points

### CRDT Integration Summary

Phoenix's CRDT integration provides:

1. **Comprehensive CRDT Library**: G-Counter, PN-Counter, OR-Set, LWW-Map with delta synchronization
2. **Multi-Tier Consistency**: Local, CRDT, consensus, and persistent state with appropriate guarantees
3. **Advanced Conflict Resolution**: Vector clock, semantic, and domain-specific resolution strategies
4. **Performance Optimization**: Compression, caching, and batching for production deployments
5. **Flexible Consistency Models**: Eventual and strong consistency based on use case requirements

### Integration with Phoenix Architecture

The CRDT system integrates seamlessly with other Phoenix components:

- **Agent State Management**: CRDTs provide the foundation for distributed agent state
- **Communication Layer**: Delta synchronization uses Phoenix's communication protocols
- **Fault Tolerance**: Anti-entropy and replication provide resilience against node failures
- **Performance Monitoring**: CRDT operations emit telemetry for observability

### Next Document Preview

The next document in the series will cover **Fault Tolerance and Partition Handling**, providing detailed specifications for:

- Network partition detection and response strategies
- Circuit breaker patterns for distributed operations
- Graceful degradation mechanisms
- Recovery protocols and state reconciliation

**This CRDT foundation enables Phoenix agents to maintain consistent state across distributed clusters while providing the flexibility to choose appropriate consistency guarantees per use case.**

---

**Document Version**: 1.0  
**Next Review**: 2025-07-19  
**Implementation Priority**: High  
**Dependencies**: Phoenix Communication Protocols (Part 2)