# Foundation Layer Refactoring Plan

Based on my research, I can now provide you with comprehensive recommendations for refactoring the foundation layer into a separate repository. Here's my analysis and recommendations:

## Current State Analysis

From my research, I can see that:

1. **You already have a separate foundation project** (`18-foundation/`) that appears to be a started refactoring effort
2. **The foundation layer is substantial** with infrastructure components like:
   - Circuit breakers, rate limiters, connection managers
   - Configuration management, event storage, telemetry services
   - Process and service registries
   - Error handling and validation systems
3. **Multiple iterations exist** across different numbered directories (16, 17, 18) showing ongoing evolution

## Best Approach for Foundation Layer Refactoring

### 1. **Project Structure & Naming**

I recommend the following structure for the standalone foundation library:

```elixir
# mix.exs
defmodule Foundation.MixProject do
  def project do
    [
      app: :foundation,
      version: "0.1.0",
      # Make it a proper OTP application
      mod: {Foundation.Application, []},
      # ...
    ]
  end
end
```

**Rationale**: Use `Foundation` rather than `FoundationLib` - it's cleaner and the package name will distinguish it from the consuming applications.

### 2. **Optimal Supervision Tree Design**

Based on your current architecture, here's the recommended supervision tree:

```elixir
# lib/foundation/application.ex
defmodule Foundation.Application do
  use Application
  
  @impl true
  def start(_type, _args) do
    children = [
      # Core registry (must start first)
      {Foundation.ProcessRegistry, []},
      
      # Foundation services
      {Foundation.Services.ConfigServer, [namespace: :production]},
      {Foundation.Services.EventStore, [namespace: :production]}, 
      {Foundation.Services.TelemetryService, [namespace: :production]},
      
      # Infrastructure protection
      {Foundation.Infrastructure.ConnectionManager, []},
      {Foundation.Infrastructure.RateLimiter.HammerBackend, [clean_period: :timer.minutes(1)]},
      
      # Task supervisor for async operations
      {Task.Supervisor, name: Foundation.TaskSupervisor}
    ]
    
    opts = [strategy: :one_for_one, name: Foundation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 3. **ElixirScope Integration Pattern**

The consuming `elixir_scope` application should:

```elixir
# elixir_scope/mix.exs
def deps do
  [
    {:foundation, github: "your_org/foundation", tag: "v0.1.0"},
    # Or for local development:
    # {:foundation, path: "../foundation"},
    # other dependencies...
  ]
end

# Ensure foundation starts before elixir_scope
def application do
  [
    mod: {ElixirScope.Application, []},
    extra_applications: [:foundation]
  ]
end
```

```elixir
# elixir_scope/lib/elixir_scope/application.ex
defmodule ElixirScope.Application do
  use Application
  
  @impl true
  def start(_type, _args) do
    # Foundation will already be started by OTP due to dependency declaration
    
    children = [
      # ElixirScope-specific supervisors
      {ElixirScope.AST.Supervisor, []},
      {ElixirScope.CPG.Supervisor, []},
      {ElixirScope.Analysis.Supervisor, []},
      {ElixirScope.Query.Supervisor, []},
      {ElixirScope.Capture.Supervisor, []},
      {ElixirScope.Intelligence.Supervisor, []},
      {ElixirScope.Debugger.Supervisor, []}
    ]
    
    opts = [strategy: :one_for_one, name: ElixirScope.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 4. **Service Discovery & Configuration**

Design the foundation to be configurable by consuming applications:

```elixir
# elixir_scope/config/config.exs
config :foundation, Foundation.Services.ConfigServer,
  some_foundation_option: :value_for_elixir_scope

config :foundation, Foundation.Infrastructure,
  circuit_breaker_provider: Foundation.Infrastructure.FuseAdapter,
  rate_limiter_provider: Foundation.Infrastructure.HammerAdapter

config :elixir_scope,
  ast_processing_option: true
```

### 5. **Key Refactoring Steps**

1. **Create the foundation repository**:
   ```bash
   mix new foundation --sup
   cd foundation
   ```

2. **Move and rename modules**:
   - `ElixirScope.Foundation.*` → `Foundation.*`
   - Update all internal references
   - Update behaviour implementations

3. **Update dependencies**:
   - Move infrastructure deps (`:fuse`, `:hammer`, `:poolboy`) to foundation
   - Add foundation as dependency in elixir_scope

4. **Service Integration**:
   ```elixir
   # In ElixirScope services that need foundation
   defmodule ElixirScope.Intelligence.AI.LLMClient do
     alias Foundation.Infrastructure
     alias Foundation.Config
     
     def call_llm_api(prompt) do
       api_key = Config.get([:llm, :api_key])
       
       Infrastructure.execute_protected(:llm_api_call, [
         circuit_breaker: :llm_breaker,
         rate_limiter: {:llm_user_rate, "user_123"},
       ], fn ->
         HTTPoison.post("llm_api_url", build_body(prompt, api_key))
       end)
     end
   end
   ```

### 6. **Testing Strategy**

```elixir
# foundation/test/test_helper.exs
# Foundation's own comprehensive test suite

# elixir_scope/test/test_helper.exs  
# Tests integration with foundation as external dependency
# Mock foundation services where needed using Mox
```

### 7. **Benefits of This Approach**

1. **Clean Separation**: Foundation is truly autonomous and reusable
2. **Proper OTP Integration**: Uses standard `applications` dependency management
3. **Fault Isolation**: Separate supervision trees prevent cascade failures
4. **Flexible Configuration**: Each consuming app can configure foundation differently
5. **Testability**: Foundation can be fully tested independently
6. **Reusability**: Other projects can consume foundation without ElixirScope dependencies

### 8. **Migration Path**

1. Complete the foundation library (seems well underway in `18-foundation/`)
2. Publish as internal git dependency or hex package
3. Update elixir_scope to consume foundation
4. Remove duplicated foundation code from elixir_scope
5. Validate all functionality works end-to-end

This architecture follows the discussion patterns you shared and provides a robust, reusable foundation that ElixirScope can build upon while maintaining clear boundaries and proper OTP application lifecycle management.
