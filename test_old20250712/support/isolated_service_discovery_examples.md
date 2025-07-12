# Isolated Service Discovery - Usage Examples

## Overview

The `Foundation.IsolatedServiceDiscovery` module provides transparent access to JidoFoundation services in isolated supervision testing environments. This enables tests to call service functions without dealing with Registry mechanics directly.

## Basic Usage

### Test Setup

```elixir
defmodule MySupervisionTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  alias Foundation.IsolatedServiceDiscovery
  
  test "basic service access", %{supervision_tree: sup_tree} do
    # Get service PID directly
    {:ok, task_pid} = IsolatedServiceDiscovery.find_service_pid(sup_tree, JidoFoundation.TaskPoolManager)
    assert is_pid(task_pid)
    assert Process.alive?(task_pid)
  end
end
```

### Calling Service Functions

```elixir
test "service function calls", %{supervision_tree: sup_tree} do
  # Simple function call (no arguments)
  stats = IsolatedServiceDiscovery.call_service(sup_tree, JidoFoundation.TaskPoolManager, :get_all_stats)
  assert is_map(stats)
  
  # Function with arguments
  result = IsolatedServiceDiscovery.call_service(
    sup_tree, 
    JidoFoundation.TaskPoolManager, 
    :create_pool, 
    [:test_pool, %{max_concurrency: 4}]
  )
  assert result == :ok
  
  # Direct tuple call
  result = IsolatedServiceDiscovery.call_service(
    sup_tree, 
    JidoFoundation.TaskPoolManager, 
    {:execute_batch, [:test_pool, [1, 2, 3], fn x -> x * 2 end, [timeout: 1000]]}
  )
  case result do
    {:ok, stream} -> 
      results = Enum.to_list(stream)
      assert length(results) == 3
    {:error, :pool_not_found} -> 
      :ok  # Pool might not be ready yet
  end
end
```

### Casting Messages

```elixir
test "service configuration", %{supervision_tree: sup_tree} do
  # Cast configuration updates
  :ok = IsolatedServiceDiscovery.cast_service(
    sup_tree, 
    JidoFoundation.TaskPoolManager, 
    {:update_config, %{default_timeout: 10000}}
  )
  
  # Cast notifications
  :ok = IsolatedServiceDiscovery.cast_service(
    sup_tree, 
    JidoFoundation.CoordinationManager,
    {:agent_status_update, agent_pid, :healthy}
  )
end
```

## Advanced Usage

### Service Discovery and Inventory

```elixir
test "service inventory", %{supervision_tree: sup_tree} do
  # List all available services
  {:ok, services} = IsolatedServiceDiscovery.list_services(sup_tree)
  
  service_modules = Enum.map(services, & &1.module)
  assert JidoFoundation.TaskPoolManager in service_modules
  assert JidoFoundation.SystemCommandManager in service_modules
  
  # Verify all services are alive
  all_alive = Enum.all?(services, & &1.alive)
  assert all_alive, "Some services are not alive"
end
```

### Waiting for Services

```elixir
test "wait for service restart", %{supervision_tree: sup_tree} do
  # Get initial service PID
  {:ok, old_pid} = IsolatedServiceDiscovery.find_service_pid(sup_tree, JidoFoundation.TaskPoolManager)
  
  # Kill the service to trigger restart
  Process.exit(old_pid, :kill)
  
  # Wait for supervisor to restart it
  {:ok, new_pid} = IsolatedServiceDiscovery.wait_for_service(
    sup_tree, 
    JidoFoundation.TaskPoolManager, 
    8000  # timeout
  )
  
  assert new_pid != old_pid
  assert Process.alive?(new_pid)
end
```

### Parallel Service Calls

```elixir
test "parallel operations", %{supervision_tree: sup_tree} do
  calls = [
    {JidoFoundation.TaskPoolManager, :get_all_stats, []},
    {JidoFoundation.SystemCommandManager, :get_stats, []},
    {JidoFoundation.CoordinationManager, :get_status, []}
  ]
  
  {:ok, results} = IsolatedServiceDiscovery.call_services_parallel(sup_tree, calls, 5000)
  
  assert length(results) == 3
  
  # Check results structure
  for result <- results do
    assert Map.has_key?(result, :module)
    assert Map.has_key?(result, :status) 
    assert Map.has_key?(result, :result)
    assert result.status in [:ok, :error]
  end
end
```

## Error Handling

### Graceful Error Handling

```elixir
test "error scenarios", %{supervision_tree: sup_tree} do
  # Missing service
  result = IsolatedServiceDiscovery.find_service_pid(sup_tree, NonExistentService)
  assert {:error, {:service_not_found, NonExistentService}} = result
  
  # Invalid context
  result = IsolatedServiceDiscovery.find_service_pid(%{}, JidoFoundation.TaskPoolManager)
  assert {:error, {:invalid_context, :missing_registry}} = result
  
  # Call timeout
  result = IsolatedServiceDiscovery.call_service(
    sup_tree, 
    JidoFoundation.TaskPoolManager, 
    :long_running_operation,
    [],
    100  # short timeout
  )
  
  case result do
    {:error, {:call_timeout, _, _}} -> :ok
    _other -> :ok  # Service might not implement this operation
  end
end
```

## Integration with Existing Helpers

The isolated service discovery integrates seamlessly with existing test helpers:

```elixir
test "combined usage", %{supervision_tree: sup_tree} do
  # Use existing supervision test helpers
  {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
  
  # Use isolated service discovery for transparent calls  
  stats = IsolatedServiceDiscovery.call_service(sup_tree, JidoFoundation.TaskPoolManager, :get_all_stats)
  
  # Both approaches work with the same supervision context
  assert is_pid(task_pid)
  assert is_map(stats)
end
```

## Migration from Direct Service Calls

### Before (Global Services)

```elixir
# DON'T DO THIS - affects global state
test "bad pattern" do
  stats = JidoFoundation.TaskPoolManager.get_all_stats()
  # This affects production services!
end
```

### After (Isolated Services)

```elixir
# DO THIS - isolated per test
test "good pattern", %{supervision_tree: sup_tree} do
  stats = IsolatedServiceDiscovery.call_service(sup_tree, JidoFoundation.TaskPoolManager, :get_all_stats)
  # This only affects this test's isolated services
end
```

## API Compatibility

The service discovery provides the same interface as direct service calls:

| Direct Call | Isolated Call |
|-------------|---------------|
| `TaskPoolManager.get_all_stats()` | `call_service(sup_tree, TaskPoolManager, :get_all_stats)` |
| `TaskPoolManager.create_pool(:test, opts)` | `call_service(sup_tree, TaskPoolManager, :create_pool, [:test, opts])` |
| `GenServer.cast(pid, msg)` | `cast_service(sup_tree, TaskPoolManager, msg)` |

This enables easy migration of existing tests to the isolated supervision pattern.