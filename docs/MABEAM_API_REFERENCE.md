# MABEAM API Reference

## Overview

This document provides a comprehensive API reference for the MABEAM (Multi-Agent BEAM) system implemented in the Foundation library. MABEAM provides multi-agent coordination capabilities with universal variable orchestration, agent lifecycle management, and sophisticated coordination protocols.

## Table of Contents

1. [Core Types (`Foundation.MABEAM.Types`)](#core-types)
2. [Core Orchestrator (`Foundation.MABEAM.Core`)](#core-orchestrator)
3. [Agent Registry (`Foundation.MABEAM.AgentRegistry`)](#agent-registry)
4. [Coordination (`Foundation.MABEAM.Coordination`)](#coordination)
5. [Auction Coordination (`Foundation.MABEAM.Coordination.Auction`)](#auction-coordination)
6. [Market Coordination (`Foundation.MABEAM.Coordination.Market`)](#market-coordination)
7. [Telemetry (`Foundation.MABEAM.Telemetry`)](#telemetry)
8. [Configuration](#configuration)
9. [Examples](#examples)

---

## Core Types

### `Foundation.MABEAM.Types`

Provides type definitions and utility functions for the MABEAM system.

#### Key Types

```elixir
@type agent_id :: atom() | String.t()
@type agent_state :: %{
  id: agent_id(),
  type: agent_type(),
  status: agent_status(),
  capabilities: [agent_capability()],
  variables: %{variable_name() => variable_value()},
  coordination_state: coordination_state(),
  metadata: agent_metadata()
}

@type universal_variable :: %{
  name: variable_name(),
  value: variable_value(),
  type: variable_type(),
  access_mode: access_mode(),
  conflict_resolution: conflict_resolution_strategy(),
  version: pos_integer(),
  last_modified: DateTime.t(),
  last_modifier: agent_id(),
  metadata: variable_metadata()
}
```

#### Utility Functions

##### `new_agent/3`

Creates a new agent state with default values.

```elixir
@spec new_agent(agent_id(), agent_type(), keyword()) :: agent_state()
```

**Parameters:**
- `id` - Unique identifier for the agent
- `type` - Agent type (`:coordinator`, `:worker`, `:monitor`, `:orchestrator`, `:hybrid`)
- `opts` - Optional configuration (capabilities, namespace, tags, custom metadata)

**Examples:**
```elixir
# Create a basic worker agent
agent = Foundation.MABEAM.Types.new_agent(:worker_1, :worker)

# Create a coordinator with custom capabilities
agent = Foundation.MABEAM.Types.new_agent("coord_1", :coordinator,
  capabilities: [:consensus, :negotiation],
  namespace: :production,
  tags: [:critical, :primary]
)
```

##### `new_variable/4`

Creates a new universal variable with default configuration.

```elixir
@spec new_variable(variable_name(), variable_value(), agent_id(), keyword()) :: universal_variable()
```

**Parameters:**
- `name` - Variable name identifier
- `value` - Initial value
- `creator` - Agent that created the variable
- `opts` - Optional configuration (type, access_mode, conflict_resolution, tags)

**Examples:**
```elixir
# Create a simple shared counter
var = Foundation.MABEAM.Types.new_variable(:counter, 0, :agent_1)

# Create a complex shared state variable
var = Foundation.MABEAM.Types.new_variable("shared_state", %{}, "coordinator",
  type: :shared,
  access_mode: :public,
  conflict_resolution: :consensus,
  tags: [:critical, :monitored]
)
```

##### `default_config/0`

Returns default MABEAM system configuration.

```elixir
@spec default_config() :: mabeam_config()
```

---

## Core Orchestrator

### `Foundation.MABEAM.Core`

Universal Variable Orchestrator for multi-agent coordination.

#### Public API

##### `start_link/1`

Starts the MABEAM Core orchestrator service.

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

**Parameters:**
- `opts` - Configuration options including `:config` and `:namespace`

**Examples:**
```elixir
# Start with default configuration
{:ok, pid} = Foundation.MABEAM.Core.start_link()

# Start with custom configuration
config = %{max_variables: 50, coordination_timeout: 10_000}
{:ok, pid} = Foundation.MABEAM.Core.start_link(config: config)
```

##### `register_orchestration_variable/1`

Registers an orchestration variable with the Core orchestrator.

```elixir
@spec register_orchestration_variable(orchestration_variable()) :: :ok | {:error, term()}
```

**Examples:**
```elixir
variable = %{
  name: :global_config,
  type: :configuration,
  access_mode: :public,
  initial_value: %{setting: "default"},
  conflict_resolution: :last_write_wins
}

:ok = Foundation.MABEAM.Core.register_orchestration_variable(variable)
```

##### `coordinate_system/0`

Initiates system-wide coordination across all registered agents and variables.

```elixir
@spec coordinate_system() :: {:ok, [coordination_result()]} | {:error, term()}
```

##### `get_system_status/0`

Retrieves comprehensive system status including variables, metrics, and health.

```elixir
@spec get_system_status() :: {:ok, system_status()} | {:error, term()}
```

---

## Agent Registry

### `Foundation.MABEAM.AgentRegistry`

Registry for managing agent lifecycle, supervision, and metadata.

#### Public API

##### `start_link/1`

Starts the Agent Registry service.

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

##### `register_agent/2`

Registers an agent with the registry.

```elixir
@spec register_agent(atom(), agent_config()) :: :ok | {:error, term()}
```

**Parameters:**
- `agent_id` - Unique agent identifier
- `config` - Agent configuration map

**Examples:**
```elixir
config = %{
  module: MyApp.WorkerAgent,
  args: [worker_id: 1, task_queue: :default],
  type: :worker,
  restart: :permanent,
  capabilities: [:variable_access, :coordination]
}

:ok = Foundation.MABEAM.AgentRegistry.register_agent(:worker_1, config)
```

##### `start_agent/1`

Starts a registered agent.

```elixir
@spec start_agent(atom()) :: {:ok, pid()} | {:error, term()}
```

##### `stop_agent/1`

Stops a running agent.

```elixir
@spec stop_agent(atom()) :: :ok | {:error, term()}
```

##### `get_agent_status/1`

Retrieves the current status of an agent.

```elixir
@spec get_agent_status(atom()) :: {:ok, agent_status()} | {:error, term()}
```

##### `list_agents/0`

Lists all registered agents.

```elixir
@spec list_agents() :: {:ok, [atom()]} | {:error, term()}
```

---

## Coordination

### `Foundation.MABEAM.Coordination`

Basic coordination protocols for multi-agent systems.

#### Public API

##### `start_link/1`

Starts the Coordination service.

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

**Options:**
- `:default_timeout` - Default timeout for coordination operations (default: 5000ms)
- `:max_concurrent_coordinations` - Maximum concurrent coordinations (default: 100)
- `:telemetry_enabled` - Enable telemetry events (default: true)

##### `register_protocol/2`

Registers a coordination protocol.

```elixir
@spec register_protocol(atom(), coordination_protocol()) :: :ok | {:error, term()}
```

**Examples:**
```elixir
protocol = %{
  name: :simple_consensus,
  type: :consensus,
  algorithm: &my_consensus_algorithm/1,
  timeout: 5000,
  retry_policy: %{max_retries: 3, backoff: :exponential}
}

:ok = Foundation.MABEAM.Coordination.register_protocol(:my_consensus, protocol)
```

##### `coordinate/3`

Executes a coordination protocol with specified agents.

```elixir
@spec coordinate(atom(), [agent_id()], map()) :: {:ok, [coordination_result()]} | {:error, term()}
```

**Parameters:**
- `protocol_name` - Name of the registered protocol
- `agent_ids` - List of participating agents
- `context` - Coordination context and parameters

**Examples:**
```elixir
{:ok, results} = Foundation.MABEAM.Coordination.coordinate(
  :simple_consensus,
  [:agent1, :agent2, :agent3],
  %{question: "Should we proceed?", options: [:yes, :no]}
)
```

##### `resolve_conflict/2`

Resolves conflicts using specified strategies.

```elixir
@spec resolve_conflict(conflict(), keyword()) :: {:ok, conflict_resolution()} | {:error, term()}
```

**Examples:**
```elixir
conflict = %{
  type: :resource_conflict,
  resource: :cpu_time,
  conflicting_requests: %{agent1: 80, agent2: 70},
  available: 100
}

{:ok, resolution} = Foundation.MABEAM.Coordination.resolve_conflict(
  conflict, 
  strategy: :priority_based
)
```

---

## Auction Coordination

### `Foundation.MABEAM.Coordination.Auction`

Auction-based coordination mechanisms for resource allocation.

#### Public API

##### `run_auction/3`

Runs an auction for resource allocation or parameter optimization.

```elixir
@spec run_auction(atom(), [map()] | [agent_id()], keyword()) :: {:ok, auction_result()} | {:error, term()}
```

**Parameters:**
- `variable_id` - Identifier for the resource or parameter being auctioned
- `bids_or_agents` - Either a list of bids or agent IDs to collect bids from
- `opts` - Auction options (type, payment_rule, timeout, etc.)

**Auction Types:**
- `:sealed_bid` - Sealed-bid auction (first or second price)
- `:english` - English (ascending) auction
- `:dutch` - Dutch (descending) auction
- `:combinatorial` - Combinatorial auction for bundles

**Examples:**
```elixir
# Sealed-bid auction with explicit bids
bids = [
  %{agent_id: :agent1, bid_amount: 100, metadata: %{}},
  %{agent_id: :agent2, bid_amount: 150, metadata: %{}},
  %{agent_id: :agent3, bid_amount: 120, metadata: %{}}
]

{:ok, result} = Foundation.MABEAM.Coordination.Auction.run_auction(
  :cpu_resource,
  bids,
  auction_type: :sealed_bid,
  payment_rule: :second_price
)

# English auction with agent collection
{:ok, result} = Foundation.MABEAM.Coordination.Auction.run_auction(
  :memory_allocation,
  [:agent1, :agent2, :agent3],
  auction_type: :english,
  starting_price: 50,
  increment: 10
)
```

##### `register_auction_protocol/2`

Registers an auction protocol with the coordination system.

```elixir
@spec register_auction_protocol(atom(), keyword()) :: :ok | {:error, term()}
```

**Examples:**
```elixir
:ok = Foundation.MABEAM.Coordination.Auction.register_auction_protocol(
  :resource_auction,
  auction_type: :sealed_bid,
  payment_rule: :second_price,
  timeout: 30_000
)
```

---

## Market Coordination

### `Foundation.MABEAM.Coordination.Market`

Market-based coordination mechanisms for resource allocation and price discovery.

#### Public API

##### `create_market/2`

Creates a new market for resource trading.

```elixir
@spec create_market(atom(), map()) :: {:ok, market_state()} | {:error, term()}
```

**Examples:**
```elixir
market_config = %{
  resource_type: :cpu_time,
  initial_price: 100,
  price_adjustment_rate: 0.1,
  max_participants: 50
}

{:ok, market} = Foundation.MABEAM.Coordination.Market.create_market(
  :cpu_market,
  market_config
)
```

##### `find_equilibrium/2`

Finds market equilibrium given supply and demand.

```elixir
@spec find_equilibrium([map()], [map()]) :: {:ok, equilibrium_result()} | {:error, term()}
```

**Examples:**
```elixir
supply = [
  %{agent_id: :supplier1, quantity: 100, min_price: 50},
  %{agent_id: :supplier2, quantity: 150, min_price: 60}
]

demand = [
  %{agent_id: :buyer1, quantity: 80, max_price: 70},
  %{agent_id: :buyer2, quantity: 120, max_price: 65}
]

{:ok, equilibrium} = Foundation.MABEAM.Coordination.Market.find_equilibrium(
  supply,
  demand
)
```

##### `simulate_market/2`

Simulates market dynamics over multiple periods.

```elixir
@spec simulate_market(atom(), map()) :: {:ok, simulation_result()} | {:error, term()}
```

**Examples:**
```elixir
simulation_config = %{
  periods: 5,
  demand_variation: 0.1,
  supply_variation: 0.05,
  learning_enabled: true,
  learning_rate: 0.1
}

{:ok, result} = Foundation.MABEAM.Coordination.Market.simulate_market(
  :dynamic_market,
  simulation_config
)
```

---

## Telemetry

### `Foundation.MABEAM.Telemetry`

MABEAM-specific telemetry and monitoring functionality.

#### Public API

##### `start_link/1`

Starts the MABEAM Telemetry service.

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

##### `record_agent_metric/3`

Records an agent performance metric.

```elixir
@spec record_agent_metric(agent_id(), metric_type(), metric_value()) :: :ok | {:error, term()}
```

**Examples:**
```elixir
# Record execution time
:ok = Foundation.MABEAM.Telemetry.record_agent_metric(
  "agent_1",
  :execution_time_ms,
  150.5
)

# Record memory usage
:ok = Foundation.MABEAM.Telemetry.record_agent_metric(
  "agent_2",
  :memory_usage_mb,
  25.3
)
```

##### `record_coordination_metric/4`

Records coordination protocol performance metrics.

```elixir
@spec record_coordination_metric(protocol_id(), metric_type(), metric_value(), map()) :: :ok | {:error, term()}
```

##### `get_agent_metrics/2`

Retrieves metrics for a specific agent.

```elixir
@spec get_agent_metrics(agent_id(), time_window()) :: {:ok, map()} | {:error, term()}
```

##### `detect_anomalies/1`

Detects performance anomalies using statistical analysis.

```elixir
@spec detect_anomalies(agent_id()) :: {:ok, [anomaly()]} | {:error, term()}
```

##### `export_dashboard_data/1`

Exports dashboard data in specified format.

```elixir
@spec export_dashboard_data(:json | :prometheus) :: {:ok, binary()} | {:error, term()}
```

---

## Configuration

### MABEAM System Configuration

MABEAM can be configured through the application environment:

```elixir
# In config/config.exs
config :foundation, Foundation.MABEAM.Core,
  max_variables: 1000,
  coordination_timeout: 5000,
  history_retention: 100,
  telemetry_enabled: true

config :foundation, Foundation.MABEAM.AgentRegistry,
  max_agents: 1000,
  health_check_interval: 30_000,
  auto_restart: true,
  resource_monitoring: true

config :foundation, Foundation.MABEAM.Coordination,
  default_timeout: 5_000,
  max_concurrent_coordinations: 100,
  protocol_timeout: 10_000

config :foundation, Foundation.MABEAM.Telemetry,
  retention_minutes: 60,
  cleanup_interval_ms: 30_000,
  anomaly_detection: true,
  anomaly_threshold: 2.0
```

---

## Examples

### Complete Multi-Agent Coordination Example

```elixir
# 1. Start MABEAM services
{:ok, _} = Foundation.MABEAM.Core.start_link()
{:ok, _} = Foundation.MABEAM.AgentRegistry.start_link()
{:ok, _} = Foundation.MABEAM.Coordination.start_link()
{:ok, _} = Foundation.MABEAM.Telemetry.start_link()

# 2. Register agents
worker_config = %{
  module: MyApp.WorkerAgent,
  args: [worker_id: 1],
  type: :worker,
  capabilities: [:variable_access, :coordination]
}

:ok = Foundation.MABEAM.AgentRegistry.register_agent(:worker_1, worker_config)
:ok = Foundation.MABEAM.AgentRegistry.register_agent(:worker_2, worker_config)

# 3. Start agents
{:ok, _pid1} = Foundation.MABEAM.AgentRegistry.start_agent(:worker_1)
{:ok, _pid2} = Foundation.MABEAM.AgentRegistry.start_agent(:worker_2)

# 4. Register coordination protocol
protocol = %{
  name: :resource_allocation,
  type: :consensus,
  algorithm: &MyApp.ConsensusAlgorithm.simple_majority/1,
  timeout: 5000
}

:ok = Foundation.MABEAM.Coordination.register_protocol(:resource_allocation, protocol)

# 5. Execute coordination
{:ok, results} = Foundation.MABEAM.Coordination.coordinate(
  :resource_allocation,
  [:worker_1, :worker_2],
  %{resource: :cpu_time, available: 100}
)

# 6. Run auction for resource allocation
bids = [
  %{agent_id: :worker_1, bid_amount: 60},
  %{agent_id: :worker_2, bid_amount: 80}
]

{:ok, auction_result} = Foundation.MABEAM.Coordination.Auction.run_auction(
  :cpu_resource,
  bids,
  auction_type: :sealed_bid,
  payment_rule: :second_price
)

# 7. Monitor performance
:ok = Foundation.MABEAM.Telemetry.record_agent_metric(:worker_1, :task_completion_time, 125.5)
{:ok, metrics} = Foundation.MABEAM.Telemetry.get_agent_metrics(:worker_1, :last_hour)
```

### Market-Based Resource Allocation

```elixir
# Create a market for CPU resources
market_config = %{
  resource_type: :cpu_time,
  initial_price: 50,
  price_adjustment_rate: 0.15
}

{:ok, market} = Foundation.MABEAM.Coordination.Market.create_market(:cpu_market, market_config)

# Define supply and demand
supply = [
  %{agent_id: :provider_1, quantity: 200, min_price: 40},
  %{agent_id: :provider_2, quantity: 150, min_price: 45}
]

demand = [
  %{agent_id: :consumer_1, quantity: 100, max_price: 60},
  %{agent_id: :consumer_2, quantity: 180, max_price: 55}
]

# Find market equilibrium
{:ok, equilibrium} = Foundation.MABEAM.Coordination.Market.find_equilibrium(supply, demand)

IO.puts("Equilibrium price: #{equilibrium.price}")
IO.puts("Quantity traded: #{equilibrium.quantity}")
```

---

## Error Handling

All MABEAM APIs use Foundation's structured error system. Common error types include:

- `:agent_not_found` - Requested agent doesn't exist
- `:coordination_failed` - Coordination protocol failed
- `:auction_invalid_bids` - Invalid bid format or values
- `:market_no_equilibrium` - No market equilibrium found
- `:telemetry_storage_error` - Telemetry storage failed

Example error handling:

```elixir
case Foundation.MABEAM.Coordination.coordinate(:invalid_protocol, [:agent1], %{}) do
  {:ok, results} -> 
    handle_success(results)
  {:error, %Foundation.Types.Error{error_type: :protocol_not_found} = error} ->
    Logger.error("Protocol not found: #{error.message}")
    handle_protocol_error(error)
  {:error, error} ->
    Logger.error("Coordination failed: #{error.message}")
    handle_general_error(error)
end
```

---

## Integration with Foundation Services

MABEAM integrates seamlessly with Foundation's core services:

- **Process Registry**: Agent process registration and discovery
- **Service Registry**: MABEAM service registration and health monitoring
- **Events**: Coordination events and audit trails
- **Telemetry**: Performance metrics and monitoring
- **Infrastructure**: Circuit breakers and rate limiting for external services

This integration provides a robust, observable, and fault-tolerant multi-agent system built on Foundation's proven infrastructure. 