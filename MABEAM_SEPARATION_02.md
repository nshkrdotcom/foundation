
# MABEAM Separation and Refactoring Plan

This document provides a detailed plan for refactoring the MABEAM feature into a separate, independent library with an optional integration layer for the Foundation framework.

## 1. Executive Summary

The goal of this refactoring is to decouple MABEAM from the Foundation framework, allowing it to be used as a standalone library for building multi-agent systems in Elixir. The key to this is to make the integration with Foundation optional, providing a clear and well-defined interface for developers to connect MABEAM to their own infrastructure or use it with the powerful features of Foundation.

The proposed solution involves:

- **Creating a new `MABEAM` library**: This will contain the core MABEAM logic, independent of Foundation.
- **Introducing an Integration Layer**: A new `MABEAM.Integration` module will act as a bridge between MABEAM and Foundation, handling process registration, telemetry, and other integrations.
- **Refactoring MABEAM modules**: The existing MABEAM modules will be updated to use the new integration layer, removing direct dependencies on Foundation.
- **Providing a clear upgrade path**: The refactoring will be done in a way that minimizes disruption to existing applications using MABEAM within the Foundation framework.

## 2. MABEAM Core Library

The first step is to create a new Mix project for the `MABEAM` library. This library will contain the core MABEAM components, refactored to be independent of Foundation.

### 2.1. Directory Structure

The new `MABEAM` library will have the following directory structure:

```
mabeam/
├── lib/
│   ├── mabeam/
│   │   ├── agent.ex
│   │   ├── agent_supervisor.ex
│   │   ├── comms.ex
│   │   ├── coordination.ex
│   │   ├── economics.ex
│   │   ├── telemetry.ex
│   │   ├── types.ex
│   │   └── integration.ex # New integration module
│   └── mabeam.ex
├── mix.exs
└── README.md
```

### 2.2. Core Modules

The core MABEAM modules will be moved to the new library and refactored to remove direct dependencies on Foundation.

- **`MABEAM.Agent`**: The core agent module will be updated to use the `MABEAM.Integration` module for process registration and telemetry.
- **`MABEAM.AgentSupervisor`**: The agent supervisor will be updated to use the `MABEAM.Integration` module for lifecycle management.
- **`MABEAM.Comms`**: The communication module will be updated to use the `MABEAM.Integration` module for agent discovery.
- **`MABEAM.Coordination`**: The coordination module will be updated to use the `MABEAM.Integration` module for agent discovery and telemetry.
- **`MABEAM.Economics`**: The economics module will remain largely unchanged, as it has no direct dependencies on Foundation.
- **`MABEAM.Telemetry`**: The telemetry module will be updated to use the `MABEAM.Integration` module for emitting telemetry events.
- **`MABEAM.Types`**: The types module will be moved to the new library and will no longer be part of the `Foundation` namespace.

## 3. The Integration Layer

The key to making the Foundation integration optional is the new `MABEAM.Integration` module. This module will provide a set of callbacks that can be implemented by a separate integration library, such as `mabeam_foundation`.

### 3.1. `MABEAM.Integration` Behaviour

The `MABEAM.Integration` module will define a behaviour with the following callbacks:

```elixir
defmodule MABEAM.Integration do
  @callback register_process(pid, name, metadata) :: :ok | {:error, any}
  @callback unregister_process(name) :: :ok | {:error, any}
  @callback find_process(name) :: {:ok, pid} | {:error, :not_found}
  @callback emit_telemetry(event, measurements, metadata) :: :ok
end
```

### 3.2. Default Implementation

The `MABEAM` library will provide a default, no-op implementation of the `MABEAM.Integration` behaviour. This will allow MABEAM to be used without any integration, with the understanding that features like process registration and telemetry will not be available.

## 4. `mabeam_foundation` Integration Library

To provide the same level of integration with Foundation as before, a new `mabeam_foundation` library will be created. This library will implement the `MABEAM.Integration` behaviour, using the `Foundation.ProcessRegistry` and `Foundation.Telemetry` modules.

### 4.1. `MABEAM.Foundation.Integration` Module

The `mabeam_foundation` library will contain a `MABEAM.Foundation.Integration` module that implements the `MABEAM.Integration` behaviour:

```elixir
defmodule MABEAM.Foundation.Integration do
  @behaviour MABEAM.Integration

  def register_process(pid, name, metadata) do
    Foundation.ProcessRegistry.register(:production, name, pid, metadata)
  end

  def unregister_process(name) do
    Foundation.ProcessRegistry.unregister(:production, name)
  end

  def find_process(name) do
    Foundation.ProcessRegistry.find(:production, name)
  end

  def emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end
end
```

### 4.2. Configuration

The `mabeam_foundation` library will be configured in the `config/config.exs` file of the application:

```elixir
config :mabeam, :integration, MABEAM.Foundation.Integration
```

## 5. Refactoring MABEAM Modules

With the integration layer in place, the MABEAM modules can be refactored to use the `MABEAM.Integration` module instead of directly calling Foundation modules.

### 5.1. Example: `MABEAM.AgentRegistry`

The `MABEAM.AgentRegistry` module will be updated to use the `MABEAM.Integration` module for process registration:

```elixir
# Before
Foundation.ProcessRegistry.register(:production, {:agent, agent_id}, pid, %{...})

# After
integration_module = Application.get_env(:mabeam, :integration, MABEAM.Integration.NoOp)
integration_module.register_process(pid, {:agent, agent_id}, %{...})
```

This change will allow the `MABEAM.AgentRegistry` to work with or without the Foundation integration, depending on the configuration.

## 6. Namespace and Module Renaming

To create a clearer delineation between the MABEAM library and the Foundation framework, the following namespaces and modules will be renamed:

- `Foundation.MABEAM` -> `MABEAM`
- `Foundation.MABEAM.AgentRegistry` -> `MABEAM.AgentRegistry`
- `Foundation.MABEAM.ProcessRegistry` -> `MABEAM.ProcessRegistry`
- `Foundation.MABEAM.Coordination` -> `MABEAM.Coordination`
- `Foundation.MABEAM.Telemetry` -> `MABEAM.Telemetry`

This will make it clear that MABEAM is a separate library, and not a feature of Foundation.

## 7. Build to Interface, Not Implementation

The refactoring will follow the principle of "build to interface, not implementation". The `MABEAM.Integration` behaviour will act as the interface, and the `mabeam_foundation` library will be one implementation of that interface. This will allow developers to create their own integrations with other frameworks or services, without having to modify the MABEAM codebase.

## 8. Conclusion

This refactoring plan provides a clear path for decoupling MABEAM from the Foundation framework, making it a more flexible and reusable library. By introducing an integration layer and following the principle of "build to interface, not implementation", we can create a more modular and maintainable codebase that will benefit both the MABEAM and Foundation ecosystems.
