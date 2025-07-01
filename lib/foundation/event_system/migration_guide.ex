defmodule Foundation.EventSystem.MigrationGuide do
  @moduledoc """
  Migration guide for transitioning to the unified event system.

  This module provides examples and helpers for migrating from
  multiple event systems to the unified Foundation.EventSystem.

  ## Migration Strategy

  The unified event system doesn't require immediate migration of all
  code. You can migrate incrementally:

  1. New code should use Foundation.EventSystem
  2. Migrate existing code module by module
  3. Legacy systems continue to work during transition

  ## Migration Examples

  ### From Direct Telemetry

  ```elixir
  # Before
  :telemetry.execute([:foundation, :cache, :hit], %{count: 1}, %{key: key})
  Foundation.Telemetry.emit([:cache, :hit], %{count: 1}, %{key: key})

  # After  
  Foundation.EventSystem.emit(:metric, [:cache, :hit], %{count: 1, key: key})
  ```

  ### From Signal Emission

  ```elixir
  # Before
  signal = %{type: :task_completed, data: %{task_id: id, result: result}}
  JidoFoundation.Bridge.emit_signal(agent_pid, signal)

  # After
  Foundation.EventSystem.emit(:signal, [:task, :completed], %{
    agent_pid: agent_pid,
    task_id: id,
    result: result
  })
  ```

  ### From Direct Logging

  ```elixir
  # Before
  Logger.info("Task completed", task_id: id, duration: duration)

  # After
  Foundation.EventSystem.emit(:notification, [:task, :completed], %{
    task_id: id,
    duration: duration
  })
  ```

  ## Compatibility Layer

  During migration, you can enable a compatibility layer that
  intercepts legacy event emissions and routes them through
  the unified system.
  """

  @doc """
  Provides a telemetry compatibility wrapper.

  Use this to gradually migrate telemetry calls to the unified system.

  ## Example

      # In your module
      import Foundation.EventSystem.MigrationGuide, only: [emit_telemetry_compat: 3]

      # Use compatibility function
      emit_telemetry_compat([:cache, :hit], %{count: 1}, %{key: "foo"})
  """
  defmacro emit_telemetry_compat(event, measurements, metadata \\ %{}) do
    quote do
      Foundation.EventSystem.emit(
        :metric,
        unquote(event),
        Map.merge(unquote(measurements), unquote(metadata))
      )
    end
  end

  @doc """
  Provides a signal compatibility wrapper.

  Use this to gradually migrate signal emissions to the unified system.
  """
  def emit_signal_compat(agent_pid, signal) do
    # Extract signal type and convert to event name
    signal_type = Map.get(signal, :type, :unknown)
    event_name = signal_type |> to_string() |> String.split("_") |> Enum.map(&String.to_atom/1)

    # Merge signal data with metadata
    event_data =
      Map.merge(
        Map.get(signal, :data, %{}),
        %{agent_pid: agent_pid, signal_id: Map.get(signal, :id)}
      )

    Foundation.EventSystem.emit(:signal, event_name, event_data)
  end

  @doc """
  Sets up telemetry handler forwarding to the unified system.

  This allows existing telemetry events to be automatically
  forwarded through the unified event system.

  ## Example

      # In your application start
      Foundation.EventSystem.MigrationGuide.setup_telemetry_forwarding([
        [:foundation, :cache, :hit],
        [:foundation, :cache, :miss],
        [:foundation, :request, :complete]
      ])
  """
  def setup_telemetry_forwarding(event_patterns) do
    Enum.each(event_patterns, fn pattern ->
      handler_id = "unified_forward_#{inspect(pattern)}"

      :telemetry.attach(
        handler_id,
        pattern,
        &forward_telemetry_event/4,
        nil
      )
    end)
  end

  defp forward_telemetry_event(event, measurements, metadata, _config) do
    # Remove the :foundation prefix if present
    event_name =
      case event do
        [:foundation | rest] -> rest
        other -> other
      end

    Foundation.EventSystem.emit(
      :metric,
      event_name,
      Map.merge(measurements, metadata)
    )
  end

  @doc """
  Provides migration statistics to track progress.

  Returns information about event system usage across the codebase.
  """
  def migration_stats do
    %{
      telemetry_handlers: length(:telemetry.list_handlers([])),
      signal_subscriptions: count_signal_subscriptions(),
      unified_events_emitted: get_unified_event_count(),
      migration_percentage: calculate_migration_percentage()
    }
  end

  defp count_signal_subscriptions do
    # This would query the signal bus for active subscriptions
    # Placeholder for now
    0
  end

  defp get_unified_event_count do
    # This would track events emitted through the unified system
    # Could be implemented with a simple counter
    0
  end

  defp calculate_migration_percentage do
    # This would analyze codebase to determine migration progress
    # Placeholder for now
    0.0
  end
end
