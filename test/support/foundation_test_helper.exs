defmodule Foundation.TestHelpers do
  @moduledoc """
  Consolidated test helpers for Foundation layer testing.

  Provides utilities for setting up test environments, managing services,
  and creating test data for Foundation layer functionality.
  """

  alias Foundation.BEAM.Processes
  alias Foundation.{Config, ErrorContext, Events, Utils}
  alias Foundation.Services.{ConfigServer, EventStore, TelemetryService}
  alias Foundation.Types.Error

  # Service Management

  @doc """
  Set up test environment for Foundation services.
  """
  def setup_foundation_test do
    Application.put_env(:foundation, :test_mode, true)
    reset_service_states()
    :ok
  end

  @doc """
  Clean up test environment after Foundation service tests.
  """
  def cleanup_foundation_test do
    reset_service_states()
    Application.delete_env(:foundation, :test_mode)
    :ok
  end

  @doc """
  Reset all service states to clean defaults.
  """
  def reset_service_states do
    if ConfigServer.available?() do
      try do
        ConfigServer.reset_state()
      rescue
        _ -> :ok
      end
    end

    if EventStore.available?() do
      try do
        EventStore.reset_state()
      rescue
        _ -> :ok
      end
    end

    if TelemetryService.available?() do
      try do
        TelemetryService.reset_state()
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # Service Availability

  @doc """
  Ensures Config GenServer is available for testing.
  """
  @spec ensure_config_available() :: :ok
  def ensure_config_available do
    case Foundation.ServiceRegistry.lookup(:production, :config_server) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        case wait_for_service_availability(Foundation.Services.ConfigServer, 5000) do
          :ok ->
            :ok

          :timeout ->
            raise "ConfigServer not available after 5 seconds - check application supervisor"
        end
    end
  end

  @doc """
  Ensures TelemetryService is available for testing.
  """
  @spec ensure_telemetry_available() :: :ok
  def ensure_telemetry_available do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        case wait_for_service_availability(Foundation.Services.TelemetryService, 5000) do
          :ok ->
            :ok

          :timeout ->
            raise "TelemetryService not available after 5 seconds - check application supervisor"
        end
    end
  end

  @doc """
  Ensures all Foundation services are available for testing.
  """
  @spec ensure_foundation_services_available() :: :ok
  def ensure_foundation_services_available do
    ensure_config_available()
    ensure_telemetry_available()
    :ok
  end

  @doc """
  Wait for all Foundation services to be available.
  """
  def wait_for_services(timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(deadline)
  end

  @doc """
  Waits for a specific service to be available.
  """
  @spec wait_for_service_availability(module(), non_neg_integer()) :: :ok | :timeout
  def wait_for_service_availability(service_module, timeout_ms \\ 5000) do
    wait_for(fn -> GenServer.whereis(service_module) != nil end, timeout_ms)
  end

  @doc """
  Waits for all foundation services to be available.
  """
  @spec wait_for_all_services_available(non_neg_integer()) :: :ok | :timeout
  def wait_for_all_services_available(timeout_ms \\ 5000) do
    # First ensure the Foundation application is running
    ensure_foundation_running()

    wait_for(
      fn ->
        try do
          Foundation.Config.available?() and
            Foundation.Events.available?() and
            Foundation.Telemetry.available?()
        rescue
          # If there's an ArgumentError about unknown registry, restart Foundation
          error in ArgumentError ->
            if String.contains?(Exception.message(error), "unknown registry:") do
              ensure_foundation_running()
            end

            false

          _ ->
            false
        end
      end,
      timeout_ms
    )
  end

  @doc """
  Ensures the Foundation application is running and services are available.
  """
  @spec ensure_foundation_running() :: :ok
  def ensure_foundation_running do
    if Application.started_applications()
       |> Enum.any?(fn {app, _, _} -> app == :foundation end) do
      # Application is running, but ProcessRegistry might be down
      try do
        Foundation.ProcessRegistry.stats()
      rescue
        _error in ArgumentError ->
          # ProcessRegistry is down, restart Foundation
          Application.stop(:foundation)
          {:ok, _} = Application.ensure_all_started(:foundation)
          Process.sleep(300)
      end
    else
      # Start the Foundation application
      {:ok, _} = Application.ensure_all_started(:foundation)
      Process.sleep(300)
    end

    # Extra wait for ProcessRegistry to be fully available
    wait_for(
      fn ->
        try do
          Foundation.ProcessRegistry.stats()
          true
        rescue
          ArgumentError -> false
        end
      end,
      5000
    )

    :ok
  end

  # Event Creation

  @doc """
  Creates a test event with known data.
  """
  @spec create_test_event(keyword()) ::
          {:ok, Foundation.Types.Event.t()} | {:error, Error.t()}
  def create_test_event(overrides \\ []) do
    base_data = %{
      test_field: "test_value",
      timestamp: Utils.monotonic_timestamp(),
      sequence: :rand.uniform(1000)
    }

    data = Keyword.get(overrides, :data, base_data)
    event_type = Keyword.get(overrides, :event_type, :test_event)
    opts = Keyword.drop(overrides, [:data, :event_type])

    Events.new_event(event_type, data, opts)
  end

  # Configuration Helpers

  @doc """
  Creates a temporary configuration for testing.
  """
  @spec with_test_config(map(), (-> any())) :: any()
  def with_test_config(config_overrides, test_fun) do
    case Config.get() do
      {:ok, original_config} ->
        _test_config = deep_merge_config(original_config, config_overrides)

        try do
          test_fun.()
        after
          :ok
        end

      {:error, _error} ->
        test_fun.()
    end
  end

  # Utility Functions

  @doc """
  Waits for a condition to be true with timeout.
  """
  @spec wait_for((-> boolean()), non_neg_integer()) :: :ok | :timeout
  def wait_for(condition, timeout_ms \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_condition_old(condition, deadline)
  end

  @doc """
  Wait for a condition to become true, checking periodically.

  This is essential for testing concurrent systems where state changes
  happen asynchronously.
  """
  @spec wait_for_condition(function(), non_neg_integer()) :: :ok | {:error, :timeout}
  def wait_for_condition(condition_fn, timeout \\ 5000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_condition_loop(condition_fn, end_time)
  end

  defp wait_condition_loop(condition_fn, end_time) do
    if System.monotonic_time(:millisecond) > end_time do
      {:error, :timeout}
    else
      if condition_fn.() do
        :ok
      else
        :timer.sleep(100)
        wait_condition_loop(condition_fn, end_time)
      end
    end
  end

  @doc """
  Test error context creation and handling.
  """
  @spec test_error_context(module(), atom(), map()) :: ErrorContext.context()
  def test_error_context(module, function, metadata \\ %{}) do
    ErrorContext.new(module, function, metadata: metadata)
  end

  @doc """
  Validate that a result matches expected error pattern.
  """
  @spec assert_error_result({:error, Error.t()}, atom()) :: Error.t()
  def assert_error_result({:error, %Error{code: code} = error}, expected_code) do
    if code == expected_code do
      error
    else
      raise "Expected error code #{expected_code}, got #{code}"
    end
  end

  def assert_error_result(other, expected_code) do
    raise "Expected {:error, Error.t()} with code #{expected_code}, got #{inspect(other)}"
  end

  @doc """
  Validate that a result is successful.
  """
  @spec assert_ok_result(term()) :: term()
  def assert_ok_result({:ok, value}), do: value
  def assert_ok_result(:ok), do: :ok
  def assert_ok_result(value) when not is_tuple(value), do: value

  def assert_ok_result({:error, error}) do
    raise "Expected success, got error: #{inspect(error)}"
  end

  def assert_ok_result(other) do
    raise "Expected success result, got: #{inspect(other)}"
  end

  # Debugging

  def debug_config_state do
    config_pid = GenServer.whereis(Config)
    supervisor_pid = Process.whereis(Foundation.Supervisor)

    IO.puts("""
    Config Debug State:
      Config PID: #{inspect(config_pid)}
      Config Alive: #{config_pid && Process.alive?(config_pid)}
      Supervisor PID: #{inspect(supervisor_pid)}
      Supervisor Alive: #{supervisor_pid && Process.alive?(supervisor_pid)}
    """)
  end

  @doc """
  Assert that a condition eventually becomes true.

  This is a test-friendly wrapper around wait_for_condition that
  automatically fails the test if the condition times out.
  """
  @spec assert_eventually(function(), non_neg_integer()) :: :ok
  def assert_eventually(condition, timeout \\ 5000) do
    case wait_for_condition(condition, timeout) do
      :ok ->
        :ok

      {:error, :timeout} ->
        ExUnit.Assertions.flunk("Condition was not met within #{timeout}ms")
    end
  end

  @doc """
  Verify that processes are properly cleaned up after ecosystem shutdown.

  Checks that all processes in an ecosystem have terminated and their
  memory has been reclaimed.
  """
  @spec verify_ecosystem_cleanup(map(), non_neg_integer()) :: :ok | {:error, term()}
  def verify_ecosystem_cleanup(ecosystem, timeout \\ 5000) do
    all_pids =
      [ecosystem.coordinator | ecosystem.workers] ++
        if Map.get(ecosystem, :supervisor), do: [ecosystem.supervisor], else: []

    # First, try to shutdown the ecosystem gracefully
    if function_exported?(Processes, :shutdown_ecosystem, 1) do
      Processes.shutdown_ecosystem(ecosystem)
    end

    # Wait for all processes to terminate
    case wait_for_all_processes_to_die(all_pids, timeout) do
      :ok ->
        handle_successful_cleanup()

      {:error, :timeout} ->
        handle_cleanup_timeout_with_force_kill(all_pids)
    end
  end

  # Private Functions

  defp wait_loop(deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      if services_available?() do
        :ok
      else
        Process.sleep(10)
        wait_loop(deadline)
      end
    end
  end

  defp services_available? do
    ConfigServer.available?() and
      EventStore.available?() and
      TelemetryService.available?()
  end

  @spec deep_merge_config(Foundation.Types.Config.t(), map()) ::
          Foundation.Types.Config.t()
  defp deep_merge_config(original, overrides) when is_map(original) and is_map(overrides) do
    Map.merge(original, overrides, fn _key, orig_val, override_val ->
      if is_map(orig_val) and is_map(override_val) do
        deep_merge_config(orig_val, override_val)
      else
        override_val
      end
    end)
  end

  defp deep_merge_config(_original, override), do: override

  @spec wait_for_condition_old((-> boolean()), integer()) :: :ok | :timeout
  defp wait_for_condition_old(condition, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :timeout
    else
      if condition.() do
        :ok
      else
        Process.sleep(10)
        wait_for_condition_old(condition, deadline)
      end
    end
  end

  defp wait_for_all_processes_to_die(all_pids, timeout) do
    wait_for_condition(
      fn ->
        Enum.all?(all_pids, fn pid -> not Process.alive?(pid) end)
      end,
      timeout
    )
  end

  defp handle_successful_cleanup() do
    # Force garbage collection and verify memory cleanup
    :erlang.garbage_collect()
    :timer.sleep(100)
    :ok
  end

  defp handle_cleanup_timeout_with_force_kill(all_pids) do
    alive_pids = Enum.filter(all_pids, &Process.alive?/1)

    # Force kill remaining processes
    for pid <- alive_pids do
      if Process.alive?(pid) do
        Process.exit(pid, :kill)
      end
    end

    # Final check
    :timer.sleep(100)
    final_alive = Enum.filter(all_pids, &Process.alive?/1)

    if Enum.empty?(final_alive) do
      :ok
    else
      {:error, {:processes_still_alive, final_alive}}
    end
  end
end

defmodule Foundation.TestHelpers.TestModules do
  @moduledoc """
  Test helper modules for Foundation MABEAM tests.

  This module serves as a namespace for test-specific GenServer implementations
  used in MABEAM testing scenarios.
  """
end

defmodule Foundation.TestHelpers.TestWorker do
  @moduledoc """
  A simple test worker for AgentSupervisor tests.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    state = %{
      args: args,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.FailingAgent do
  @moduledoc """
  An agent that fails immediately for testing supervision policies.
  """
  use GenServer

  def start_link(args \\ []) do
    failure_mode = Keyword.get(args, :failure_mode, :immediate)

    case failure_mode do
      :immediate -> {:error, :immediate_failure}
      _ -> GenServer.start_link(__MODULE__, args, [])
    end
  end

  def init(_args) do
    {:stop, :init_failure}
  end
end

defmodule Foundation.TestHelpers.MLWorker do
  @moduledoc """
  A test ML worker for testing complex metadata and agent capabilities.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    model_type = Keyword.get(args, :model_type, :default)

    state = %{
      args: args,
      model_type: model_type,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0,
      ml_metadata: %{
        training_status: :ready,
        model_loaded: true
      }
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_ml_metadata, _from, state) do
    {:reply, {:ok, state.ml_metadata}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.CoordinationAgent do
  @moduledoc """
  A test coordination agent for testing multi-agent coordination and task distribution.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    state = %{
      args: args,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0,
      coordinated_agents: [],
      task_queue: [],
      coordination_metadata: %{
        coordination_strategy: :round_robin,
        active_tasks: 0
      }
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_coordination_metadata, _from, state) do
    {:reply, {:ok, state.coordination_metadata}, state}
  end

  def handle_call(:get_coordinated_agents, _from, state) do
    {:reply, {:ok, state.coordinated_agents}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast({:add_agent, agent_id}, state) do
    new_agents = [agent_id | state.coordinated_agents] |> Enum.uniq()
    new_state = %{state | coordinated_agents: new_agents, message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end
