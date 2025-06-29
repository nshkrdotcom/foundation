defmodule Foundation.ServiceIntegration.SignalCoordinator do
  @moduledoc """
  Addresses Category 2 signal pipeline race conditions by providing
  coordination mechanisms for deterministic signal routing.

  ## Problem Statement

  The original signal pipeline had inherent race conditions between synchronous
  signal emission and asynchronous routing. This module provides coordination
  mechanisms to make signal routing deterministic and reliable in test environments.

  ## Features

  - Synchronous signal emission with asynchronous routing coordination
  - Batch signal coordination for multiple signals
  - Telemetry-based coordination without recursive loops
  - Timeout handling and error recovery
  - Integration with existing signal infrastructure

  ## Usage

      # Emit signal synchronously and wait for routing completion
      {:ok, result} = Foundation.ServiceIntegration.SignalCoordinator.emit_signal_sync(
        agent,
        signal,
        timeout: 5000
      )

      # Wait for multiple signals to be processed
      {:ok, :all_signals_processed} = Foundation.ServiceIntegration.SignalCoordinator.wait_for_signal_processing(
        ["signal1", "signal2", "signal3"],
        timeout: 10000
      )

      # Create coordination mechanism for test scenarios
      {:ok, coordinator} = Foundation.ServiceIntegration.SignalCoordinator.start_coordination_session()
  """

  require Logger

  @type signal_id :: String.t() | atom()
  @type coordination_result :: %{
          signal_id: signal_id(),
          handlers_notified: non_neg_integer(),
          routing_time_ms: non_neg_integer()
        }
  @type coordination_session :: %{
          session_id: reference(),
          active_signals: MapSet.t(),
          results: [coordination_result()],
          started_at: integer()
        }

  @doc """
  Emits a signal synchronously and waits for routing completion.

  This addresses Category 2 race conditions by creating a coordination mechanism
  for the sync-to-async transition in signal routing.

  ## Parameters

  - `agent` - The agent emitting the signal
  - `signal` - The signal to emit
  - `opts` - Options including timeout and bus configuration

  ## Options

  - `:timeout` - Maximum wait time in ms (default: 5000)
  - `:bus` - Signal bus to use (default: :foundation_signal_bus)

  ## Returns

  - `{:ok, coordination_result()}` - Signal successfully routed
  - `{:error, reason}` - Signal routing failed or timed out
  """
  @spec emit_signal_sync(pid(), map(), keyword()) ::
          {:ok, coordination_result()} | {:error, term()}
  def emit_signal_sync(agent, signal, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    signal_bus = Keyword.get(opts, :bus, :foundation_signal_bus)

    # Create coordination mechanism for this specific signal
    coordination_ref = make_ref()
    test_pid = self()
    signal_id = Map.get(signal, :id, generate_signal_id())

    # Attach temporary telemetry handler for this specific signal
    handler_id = "sync_coordination_#{inspect(coordination_ref)}"

    start_time = System.monotonic_time()

    result =
      try do
        # Set up coordination telemetry handler
        :telemetry.attach(
          handler_id,
          [:jido, :signal, :routed],
          fn _event, measurements, metadata, _config ->
            if metadata[:signal_id] == signal_id do
              routing_time =
                System.convert_time_unit(
                  System.monotonic_time() - start_time,
                  :native,
                  :millisecond
                )

              send(
                test_pid,
                {coordination_ref, :routing_complete,
                 %{
                   signal_id: signal_id,
                   handlers_notified: measurements[:handlers_count] || 0,
                   routing_time_ms: routing_time
                 }}
              )
            end
          end,
          nil
        )

        # Emit signal asynchronously
        case emit_signal_safely(agent, Map.put(signal, :id, signal_id), signal_bus) do
          :ok ->
            # Wait synchronously for routing completion
            receive do
              {^coordination_ref, :routing_complete, result} ->
                {:ok, result}
            after
              timeout ->
                Logger.warning("Signal routing timeout",
                  signal_id: signal_id,
                  timeout: timeout
                )

                {:error, {:routing_timeout, timeout}}
            end

          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
      after
        # Always clean up telemetry handler
        try do
          :telemetry.detach(handler_id)
        catch
          _, _ -> :ok
        end
      end

    # Emit coordination telemetry
    duration = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    :telemetry.execute(
      [:foundation, :service_integration, :signal_coordination],
      %{duration: duration},
      %{result: elem(result, 0), signal_id: signal_id}
    )

    result
  end

  @doc """
  Waits for multiple signals to be processed.

  This provides batch coordination for multiple signals, useful in test scenarios
  where you need to ensure all signals have been routed before proceeding.

  ## Parameters

  - `signal_ids` - List of signal IDs to wait for
  - `timeout` - Maximum wait time in ms (default: 5000)

  ## Returns

  - `{:ok, :all_signals_processed}` - All signals processed successfully
  - `{:error, {:signals_not_processed, remaining}}` - Some signals not processed
  """
  @spec wait_for_signal_processing([signal_id()], non_neg_integer()) ::
          {:ok, :all_signals_processed} | {:error, term()}
  def wait_for_signal_processing(signal_ids, timeout \\ 5000) when is_list(signal_ids) do
    # Batch coordination for multiple signals
    coordination_ref = make_ref()
    test_pid = self()
    remaining_signals = MapSet.new(signal_ids)

    handler_id = "batch_coordination_#{inspect(coordination_ref)}"

    start_time = System.monotonic_time()

    result =
      try do
        :telemetry.attach(
          handler_id,
          [:jido, :signal, :routed],
          fn _event, _measurements, metadata, _config ->
            signal_id = metadata[:signal_id]

            if signal_id in remaining_signals do
              send(test_pid, {coordination_ref, :signal_routed, signal_id})
            end
          end,
          nil
        )

        wait_for_all_signals(coordination_ref, remaining_signals, timeout)
      after
        try do
          :telemetry.detach(handler_id)
        catch
          _, _ -> :ok
        end
      end

    # Emit batch coordination telemetry
    duration = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    :telemetry.execute(
      [:foundation, :service_integration, :batch_signal_coordination],
      %{duration: duration, signal_count: length(signal_ids)},
      %{result: elem(result, 0)}
    )

    result
  end

  @doc """
  Creates a coordination session for managing multiple signal operations.

  This is useful for complex test scenarios where you need to coordinate
  multiple signal emissions and wait for their completion.

  ## Returns

  - `{:ok, coordination_session()}` - New coordination session
  """
  @spec start_coordination_session() :: {:ok, coordination_session()}
  def start_coordination_session do
    session = %{
      session_id: make_ref(),
      active_signals: MapSet.new(),
      results: [],
      started_at: System.monotonic_time()
    }

    {:ok, session}
  end

  @doc """
  Adds a signal to an active coordination session.

  ## Parameters

  - `session` - The coordination session
  - `signal_id` - Signal ID to track

  ## Returns

  - Updated coordination session
  """
  @spec add_signal_to_session(coordination_session(), signal_id()) :: coordination_session()
  def add_signal_to_session(session, signal_id) do
    %{session | active_signals: MapSet.put(session.active_signals, signal_id)}
  end

  @doc """
  Waits for all signals in a coordination session to complete.

  ## Parameters

  - `session` - The coordination session
  - `timeout` - Maximum wait time in ms (default: 10000)

  ## Returns

  - `{:ok, updated_session}` - All signals completed
  - `{:error, reason}` - Timeout or other error
  """
  @spec wait_for_session_completion(coordination_session(), non_neg_integer()) ::
          {:ok, coordination_session()} | {:error, term()}
  def wait_for_session_completion(session, timeout \\ 10000) do
    signal_ids = MapSet.to_list(session.active_signals)

    case wait_for_signal_processing(signal_ids, timeout) do
      {:ok, :all_signals_processed} ->
        completed_session = %{
          session
          | active_signals: MapSet.new(),
            results: session.results ++ collect_session_results(signal_ids)
        }

        {:ok, completed_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Provides a test-friendly wrapper for signal emission that handles edge cases.

  This is specifically designed for test environments where you need reliable
  signal coordination without race conditions.

  ## Parameters

  - `agent` - The agent emitting the signal
  - `signal` - The signal to emit
  - `expectations` - What to expect (handler count, etc.)
  - `opts` - Additional options

  ## Returns

  - `{:ok, coordination_result()}` - Signal emitted and routed successfully
  - `{:error, reason}` - Emission or routing failed
  """
  @spec emit_signal_with_expectations(pid(), map(), map(), keyword()) ::
          {:ok, coordination_result()} | {:error, term()}
  def emit_signal_with_expectations(agent, signal, expectations, opts \\ []) do
    expected_handlers = Map.get(expectations, :handler_count, 0)

    case emit_signal_sync(agent, signal, opts) do
      {:ok, result} ->
        # Validate expectations
        if result.handlers_notified >= expected_handlers do
          {:ok, result}
        else
          {:error,
           {:expectation_failed,
            %{
              expected_handlers: expected_handlers,
              actual_handlers: result.handlers_notified,
              result: result
            }}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Debugging utility to check signal system coordination health.

  Returns information about signal routing performance and any detected issues.
  """
  @spec coordination_health_check() :: %{
          telemetry_system: :healthy | {:unhealthy, term()},
          signal_bus: {:healthy | :degraded | :unavailable, term()},
          coordination_issues: [term()],
          health_check_duration_ms: non_neg_integer(),
          timestamp: DateTime.t()
        }
  def coordination_health_check do
    start_time = System.monotonic_time()

    # Test basic telemetry system
    telemetry_health = test_telemetry_system()

    # Test signal bus availability
    signal_bus_health = test_signal_bus_availability()

    # Check for common coordination issues
    coordination_issues = detect_coordination_issues()

    duration = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    %{
      telemetry_system: telemetry_health,
      signal_bus: signal_bus_health,
      coordination_issues: coordination_issues,
      health_check_duration_ms: duration,
      timestamp: DateTime.utc_now()
    }
  end

  ## Private Functions

  defp wait_for_all_signals(coordination_ref, remaining_signals, timeout) do
    if MapSet.size(remaining_signals) == 0 do
      {:ok, :all_signals_processed}
    else
      receive do
        {^coordination_ref, :signal_routed, signal_id} ->
          new_remaining = MapSet.delete(remaining_signals, signal_id)
          wait_for_all_signals(coordination_ref, new_remaining, timeout)
      after
        timeout ->
          {:error, {:signals_not_processed, MapSet.to_list(remaining_signals)}}
      end
    end
  end

  defp emit_signal_safely(agent, signal, signal_bus) do
    try do
      # Use JidoFoundation.Bridge if available, otherwise direct emission
      if Code.ensure_loaded?(JidoFoundation.Bridge) do
        JidoFoundation.Bridge.emit_signal(agent, signal, bus: signal_bus)
      else
        # Fallback to direct signal emission
        emit_signal_direct(signal, signal_bus)
      end
    rescue
      exception ->
        Logger.error("Exception during signal emission",
          exception: inspect(exception),
          signal_id: Map.get(signal, :id)
        )

        {:error, {:emission_exception, exception}}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} during signal emission",
          reason: inspect(reason),
          signal_id: Map.get(signal, :id)
        )

        {:error, {:emission_caught, {kind, reason}}}
    end
  end

  defp emit_signal_direct(signal, signal_bus) do
    case Process.whereis(signal_bus) do
      nil ->
        {:error, {:signal_bus_not_available, signal_bus}}

      pid ->
        try do
          GenServer.cast(pid, {:emit_signal, signal})
          :ok
        catch
          kind, reason ->
            {:error, {:signal_bus_error, {kind, reason}}}
        end
    end
  end

  defp generate_signal_id do
    "coord_signal_#{:erlang.unique_integer([:positive])}"
  end

  defp collect_session_results(signal_ids) do
    # Create placeholder results for session completion
    Enum.map(signal_ids, fn signal_id ->
      %{
        signal_id: signal_id,
        # Would be filled in by actual coordination
        handlers_notified: 0,
        routing_time_ms: 0
      }
    end)
  end

  defp test_telemetry_system do
    try do
      # Test basic telemetry functionality
      test_event = [:foundation, :service_integration, :test]
      test_measurements = %{test: 1}
      test_metadata = %{test: true}

      :telemetry.execute(test_event, test_measurements, test_metadata)
      :healthy
    rescue
      exception ->
        {:unhealthy, {:telemetry_exception, exception}}
    catch
      kind, reason ->
        {:unhealthy, {:telemetry_error, {kind, reason}}}
    end
  end

  defp test_signal_bus_availability do
    case Process.whereis(Foundation.Services.SignalBus) do
      nil ->
        {:unavailable, :signal_bus_not_running}

      pid ->
        try do
          # Simple ping to check if signal bus is responsive
          GenServer.call(Foundation.Services.SignalBus, :health_check, 1000)
          {:healthy, %{pid: pid}}
        catch
          :exit, {:timeout, _} -> {:degraded, {:timeout, pid}}
          :exit, {:noproc, _} -> {:unavailable, :signal_bus_died}
          _kind, _reason -> {:healthy, %{pid: pid, note: :non_standard_health_check}}
        end
    end
  end

  defp detect_coordination_issues do
    issues = []

    # Check for common telemetry issues
    issues =
      if has_telemetry_handlers_leak?() do
        [{:telemetry_handlers_leak, "Too many active telemetry handlers detected"} | issues]
      else
        issues
      end

    # Check for signal bus overload
    issues =
      if is_signal_bus_overloaded?() do
        [{:signal_bus_overload, "Signal bus message queue is large"} | issues]
      else
        issues
      end

    issues
  end

  defp has_telemetry_handlers_leak? do
    try do
      handlers = :telemetry.list_handlers([])

      coordination_handlers =
        Enum.filter(handlers, fn handler ->
          String.contains?(handler.id, "coordination")
        end)

      # Threshold for "too many"
      length(coordination_handlers) > 10
    catch
      _, _ -> false
    end
  end

  defp is_signal_bus_overloaded? do
    case Process.whereis(Foundation.Services.SignalBus) do
      nil ->
        false

      pid ->
        try do
          {:message_queue_len, queue_len} = Process.info(pid, :message_queue_len)
          # Threshold for "overloaded"
          queue_len > 100
        catch
          _, _ -> false
        end
    end
  end
end
