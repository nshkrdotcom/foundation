# Simple Foundation Perimeter Architecture

## 🎯 **Core Principle: Validate Where It Matters**

Foundation Perimeter has exactly **three validation modes**:

1. **`:external`** - Strict validation for untrusted input
2. **`:internal`** - Light validation for service boundaries  
3. **`:trusted`** - No validation for performance paths

That's it. No zones, no enterprise architecture, no performance theaters.

## 🏗️ **Simple Architecture**

```elixir
Foundation.Perimeter
├── validate_external/2   # Strict validation with Ecto
├── validate_internal/2   # Light validation, mostly type checks
└── validate_trusted/2    # Returns {:ok, data} immediately
```

## 📝 **Usage Examples**

### External API Validation
```elixir
defmodule MyApp.API do
  use Foundation.Perimeter
  
  def create_program(params) do
    with {:ok, validated} <- validate_external(params, %{
           name: {:string, required: true, min: 1, max: 100},
           config: {:map, required: true},
           user_id: {:integer, required: true}
         }) do
      Foundation.Programs.create(validated)
    end
  end
end
```

### Internal Service Validation
```elixir
defmodule Foundation.Services.TaskManager do
  use Foundation.Perimeter
  
  def execute_task(task_data) do
    with {:ok, validated} <- validate_internal(task_data, %{
           task_id: :string,
           type: :atom,
           payload: :map
         }) do
      # Light validation just ensures basic structure
      do_execute_task(validated)
    end
  end
end
```

### Trusted High-Performance Paths
```elixir
defmodule Foundation.Core.SignalRouter do
  use Foundation.Perimeter
  
  def route_signal(signal) do
    # No validation overhead for hot paths
    {:ok, validated} = validate_trusted(signal, :any)
    fast_route(validated)
  end
end
```

## 🎭 **What We Avoided**

### ❌ **Overengineered Original**
- Four zones with grandiose names
- Multiple GenServers for validation
- ETS caching with TTL management
- Hot-path detection and adaptive optimization
- Performance profiling and telemetry integration
- Custom DSLs and compile-time generation
- Circuit breakers for validation (!?)
- Trust levels and enforcement configurations

### ✅ **Simple Reality**
- Three functions
- Use existing validation libraries
- Clear boundaries based on trust level
- Add complexity only when proven necessary

## 🚀 **Performance Characteristics**

- **External validation**: ~1-2ms (using Ecto)
- **Internal validation**: ~0.1ms (basic type checks)
- **Trusted paths**: ~0ms (immediate return)

No caching needed. No optimization required. Just fast-by-default validation.

## 🧪 **Testing Strategy**

```elixir
defmodule Foundation.PerimeterTest do
  use ExUnit.Case
  
  test "external validation rejects invalid data" do
    assert {:error, _} = Foundation.Perimeter.validate_external(
      %{name: ""}, 
      %{name: {:string, required: true, min: 1}}
    )
  end
  
  test "internal validation is permissive" do
    assert {:ok, %{}} = Foundation.Perimeter.validate_internal(%{}, %{})
  end
  
  test "trusted validation always succeeds" do
    assert {:ok, "anything"} = Foundation.Perimeter.validate_trusted("anything", :any)
  end
end
```

No event-driven testing complexity. No telemetry assertions. Just simple, clear tests.

## 🎉 **The Innovation**

The real innovation isn't complex architecture - it's **strategic simplicity**:

1. **Clear boundaries** between trust levels
2. **Appropriate validation** for each context
3. **No validation overhead** where performance matters
4. **Use proven tools** instead of building frameworks

This solves 90% of validation needs with 10% of the complexity.