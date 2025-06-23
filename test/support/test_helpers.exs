defmodule Foundation.MABEAM.TestHelpers do
  @moduledoc """
  Comprehensive test utilities for MABEAM system testing.

  Provides helper functions for:
  - Agent creation and management
  - Variable registration and validation
  - Coordination setup and verification
  - Performance testing utilities
  - Test data generation
  - Common assertions
  """

  alias Foundation.MABEAM.{AgentRegistry, Core, Coordination, Types}

  # ============================================================================
  # Agent Test Helpers
  # ============================================================================

  @doc """
  Creates and registers a test agent with default configuration.
  """
  @spec create_test_agent(atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def create_test_agent(agent_id, opts \\ []) do
    module = Keyword.get(opts, :module, Foundation.MABEAM.TestAgent)

    config = %{
      id: agent_id,
      type: :worker,
      module: module,
      config: Keyword.get(opts, :config, %{agent_id: agent_id}),
      supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
    }

    with :ok <- AgentRegistry.register_agent(agent_id, config),
         {:ok, pid} <- AgentRegistry.start_agent(agent_id) do
      {:ok, pid}
    end
  end

  @doc """
  Creates multiple test agents concurrently.
  """
  @spec create_test_agents(non_neg_integer(), keyword()) :: [atom()]
  def create_test_agents(count, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "test_agent")

    tasks =
      for i <- 1..count do
        Task.async(fn ->
          agent_id = :"#{prefix}_#{i}"

          case create_test_agent(agent_id, opts) do
            {:ok, _pid} -> agent_id
            {:error, _} -> nil
          end
        end)
      end

    tasks
    |> Task.await_many(10_000)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Cleans up test agents.
  """
  @spec cleanup_test_agents([atom()]) :: :ok
  def cleanup_test_agents(agent_ids) do
    tasks =
      for agent_id <- agent_ids do
        Task.async(fn ->
          AgentRegistry.stop_agent(agent_id)
          AgentRegistry.deregister_agent(agent_id)
        end)
      end

    Task.await_many(tasks, 10_000)
    :ok
  end

  @doc """
  Waits for agents to reach a specific status.
  """
  @spec wait_for_agent_status(atom(), atom(), non_neg_integer()) :: :ok | {:error, :timeout}
  def wait_for_agent_status(agent_id, expected_status, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_agent_status_loop(agent_id, expected_status, deadline)
  end

  defp wait_for_agent_status_loop(agent_id, expected_status, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case AgentRegistry.get_agent_status(agent_id) do
        {:ok, %{status: ^expected_status}} ->
          :ok

        _ ->
          Process.sleep(50)
          wait_for_agent_status_loop(agent_id, expected_status, deadline)
      end
    end
  end

  # ============================================================================
  # Variable Test Helpers
  # ============================================================================

  @doc """
  Creates a test universal variable.
  """
  @spec create_test_variable(atom(), term(), keyword()) :: map()
  def create_test_variable(name, value, opts \\ []) do
    modifier = Keyword.get(opts, :modifier, :test_system)
    Types.new_variable(name, value, modifier, opts)
  end

  @doc """
  Creates multiple test variables.
  """
  @spec create_test_variables(non_neg_integer(), keyword()) :: [map()]
  def create_test_variables(count, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "test_var")

    for i <- 1..count do
      name = :"#{prefix}_#{i}"
      value = %{index: i, data: "test_value_#{i}"}
      create_test_variable(name, value, opts)
    end
  end

  # ============================================================================
  # Coordination Test Helpers
  # ============================================================================

  @doc """
  Registers a test coordination protocol.
  """
  @spec register_test_protocol(atom(), keyword()) :: :ok | {:error, term()}
  def register_test_protocol(name, opts \\ []) do
    protocol = %{
      name: name,
      type: Keyword.get(opts, :type, :consensus),
      algorithm: Keyword.get(opts, :algorithm, :majority_vote),
      timeout: Keyword.get(opts, :timeout, 5000),
      retry_policy: Keyword.get(opts, :retry_policy, %{})
    }

    Coordination.register_protocol(name, protocol)
  end

  @doc """
  Creates a coordination request.
  """
  @spec create_coordination_request(atom(), atom(), map()) :: map()
  def create_coordination_request(protocol, type, params) do
    Types.new_coordination_request(protocol, type, params)
  end

  # ============================================================================
  # Performance Test Helpers
  # ============================================================================

  @doc """
  Measures execution time of a function.
  """
  @spec measure_time(function()) :: {non_neg_integer(), term()}
  def measure_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000
    {duration_ms, result}
  end

  @doc """
  Runs a function multiple times and calculates average execution time.
  """
  @spec benchmark(function(), non_neg_integer()) :: %{avg_time_ms: float(), results: [term()]}
  def benchmark(fun, iterations \\ 10) do
    results =
      for _i <- 1..iterations do
        measure_time(fun)
      end

    times = Enum.map(results, fn {time, _result} -> time end)
    return_values = Enum.map(results, fn {_time, result} -> result end)

    avg_time_ms = Enum.sum(times) / length(times)

    %{
      avg_time_ms: avg_time_ms,
      min_time_ms: Enum.min(times),
      max_time_ms: Enum.max(times),
      results: return_values
    }
  end

  @doc """
  Monitors memory usage during test execution.
  """
  @spec monitor_memory(function()) :: %{
          memory_before: non_neg_integer(),
          memory_after: non_neg_integer(),
          memory_diff: integer(),
          result: term()
        }
  def monitor_memory(fun) do
    # Force garbage collection before measurement
    :erlang.garbage_collect()
    Process.sleep(10)

    memory_before = :erlang.memory(:total)
    result = fun.()

    # Force garbage collection after execution
    :erlang.garbage_collect()
    Process.sleep(10)

    memory_after = :erlang.memory(:total)
    memory_diff = memory_after - memory_before

    %{
      memory_before: memory_before,
      memory_after: memory_after,
      memory_diff: memory_diff,
      result: result
    }
  end

  # ============================================================================
  # Concurrent Testing Helpers
  # ============================================================================

  @doc """
  Runs multiple tasks concurrently and collects results.
  """
  @spec run_concurrent_tasks([function()], non_neg_integer()) :: [term()]
  def run_concurrent_tasks(functions, timeout \\ 10_000) do
    tasks = Enum.map(functions, &Task.async/1)
    Task.await_many(tasks, timeout)
  end

  @doc """
  Runs the same function concurrently multiple times.
  """
  @spec run_concurrent_identical(function(), non_neg_integer(), non_neg_integer()) :: [term()]
  def run_concurrent_identical(fun, count, timeout \\ 10_000) do
    functions = for _i <- 1..count, do: fun
    run_concurrent_tasks(functions, timeout)
  end

  # ============================================================================
  # Data Generation Helpers
  # ============================================================================

  @doc """
  Generates random test data.
  """
  @spec generate_test_data(atom(), keyword()) :: term()
  def generate_test_data(type, opts \\ [])

  def generate_test_data(:string, opts) do
    length = Keyword.get(opts, :length, 10)
    for _i <- 1..length, into: "", do: <<Enum.random(?a..?z)>>
  end

  def generate_test_data(:integer, opts) do
    min = Keyword.get(opts, :min, 1)
    max = Keyword.get(opts, :max, 1000)
    Enum.random(min..max)
  end

  def generate_test_data(:map, opts) do
    size = Keyword.get(opts, :size, 3)

    for i <- 1..size, into: %{} do
      {:"key_#{i}", "value_#{i}"}
    end
  end

  def generate_test_data(:list, opts) do
    size = Keyword.get(opts, :size, 5)
    for i <- 1..size, do: "item_#{i}"
  end

  # ============================================================================
  # Assertion Helpers
  # ============================================================================

  @doc """
  Asserts that a function completes within a timeout.
  """
  @spec assert_completes_within(function(), non_neg_integer()) :: term()
  def assert_completes_within(fun, timeout_ms) do
    task = Task.async(fun)

    try do
      Task.await(task, timeout_ms)
    catch
      :exit, {:timeout, _} ->
        raise "Function did not complete within #{timeout_ms}ms"
    end
  end

  @doc """
  Asserts that all elements in a list match a pattern.
  """
  @spec assert_all_match([term()], (term() -> boolean())) :: :ok
  def assert_all_match(list, matcher) do
    failures = Enum.reject(list, matcher)

    if length(failures) > 0 do
      raise "#{length(failures)} elements did not match: #{inspect(failures)}"
    end

    :ok
  end

  @doc """
  Asserts that a percentage of elements match a condition.
  """
  @spec assert_success_rate([term()], (term() -> boolean()), float()) :: :ok
  def assert_success_rate(list, matcher, min_success_rate) do
    total = length(list)
    successes = Enum.count(list, matcher)
    success_rate = successes / total

    if success_rate < min_success_rate do
      raise "Success rate #{success_rate * 100}% is below minimum #{min_success_rate * 100}%"
    end

    :ok
  end

  # ============================================================================
  # System State Helpers
  # ============================================================================

  @doc """
  Gets current system state for comparison.
  """
  @spec get_system_snapshot() :: map()
  def get_system_snapshot() do
    {:ok, core_stats} = Core.get_system_statistics()
    {:ok, agent_health} = AgentRegistry.system_health()
    {:ok, coordination_stats} = Coordination.get_coordination_stats()

    %{
      core_stats: core_stats,
      agent_health: agent_health,
      coordination_stats: coordination_stats,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Compares two system snapshots.
  """
  @spec compare_system_snapshots(map(), map()) :: map()
  def compare_system_snapshots(before, after_snapshot) do
    %{
      time_diff_seconds: DateTime.diff(after_snapshot.timestamp, before.timestamp, :second),
      core_stats_diff: diff_maps(before.core_stats, after_snapshot.core_stats),
      agent_health_diff: diff_maps(before.agent_health, after_snapshot.agent_health),
      coordination_stats_diff:
        diff_maps(before.coordination_stats, after_snapshot.coordination_stats)
    }
  end

  defp diff_maps(map1, map2) do
    common_keys = MapSet.intersection(MapSet.new(Map.keys(map1)), MapSet.new(Map.keys(map2)))

    for key <- common_keys, into: %{} do
      val1 = Map.get(map1, key)
      val2 = Map.get(map2, key)

      diff =
        case {val1, val2} do
          {v1, v2} when is_number(v1) and is_number(v2) -> v2 - v1
          {v1, v2} -> {v1, v2}
        end

      {key, diff}
    end
  end

  # ============================================================================
  # Wait Helpers
  # ============================================================================

  @doc """
  Waits for a condition to become true.
  """
  @spec wait_for(function(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, :timeout}
  def wait_for(condition_fun, timeout_ms \\ 5000, check_interval_ms \\ 100) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_loop(condition_fun, deadline, check_interval_ms)
  end

  defp wait_for_loop(condition_fun, deadline, check_interval_ms) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      if condition_fun.() do
        :ok
      else
        Process.sleep(check_interval_ms)
        wait_for_loop(condition_fun, deadline, check_interval_ms)
      end
    end
  end
end

# Basic test agent for use in tests
defmodule Foundation.MABEAM.TestAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    agent_id = Map.get(args, :agent_id, :unknown)
    {:ok, %{agent_id: agent_id, message_count: 0, test_data: %{}}}
  end

  def handle_call(:health_check, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call({:echo, message}, _from, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:reply, {:ok, {:echo_response, message}}, new_state}
  end

  def handle_call({:store_data, key, value}, _from, state) do
    new_test_data = Map.put(state.test_data, key, value)
    new_state = %{state | test_data: new_test_data}
    {:reply, :ok, new_state}
  end

  def handle_call({:get_data, key}, _from, state) do
    value = Map.get(state.test_data, key)
    {:reply, {:ok, value}, state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      message_count: state.message_count,
      data_keys: Map.keys(state.test_data)
    }

    {:reply, {:ok, stats}, state}
  end

  def handle_call({:mabeam_coordination_request, _session_id, protocol, data}, _from, state) do
    response =
      case protocol do
        :simple_consensus ->
          # Randomly vote
          vote = if :rand.uniform() > 0.3, do: :proceed, else: :abort
          {:vote, vote}

        :negotiation ->
          # Provide a test offer
          offer = %{resource: data.resource, price: :rand.uniform(100)}
          {:offer, offer}

        _ ->
          {:error, :unsupported_protocol}
      end

    {:reply, {:ok, response}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end
