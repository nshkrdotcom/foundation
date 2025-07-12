defmodule Foundation.Telemetry.LoadTest do
  @moduledoc """
  Telemetry-based load testing framework for Foundation applications.

  This module provides a powerful framework for conducting load tests while
  collecting detailed telemetry metrics. It supports concurrent load generation,
  custom scenarios, and comprehensive performance analysis.

  ## Features

  - Concurrent load generation with configurable concurrency
  - Telemetry-based metrics collection
  - Custom scenario definitions
  - Real-time performance monitoring
  - Automatic report generation
  - Support for ramp-up and sustained load patterns

  ## Example

      defmodule MyLoadTest do
        use Foundation.Telemetry.LoadTest

        @impl true
        def scenarios do
          [
            %{
              name: :cache_reads,
              weight: 60,
              run: fn ctx ->
                key = "user:#{:rand.uniform(1000)}"
                Foundation.Infrastructure.Cache.get(key)
              end
            },
            %{
              name: :cache_writes,
              weight: 40,
              run: fn ctx ->
                key = "user:#{:rand.uniform(1000)}"
                Foundation.Infrastructure.Cache.put(key, %{name: "User"})
              end
            }
          ]
        end
      end

      # Run the load test
      Foundation.Telemetry.LoadTest.run(MyLoadTest,
        duration: :timer.seconds(60),
        concurrency: 100,
        ramp_up: :timer.seconds(10)
      )
  """

  require Logger

  @type scenario :: %{
          name: atom(),
          weight: non_neg_integer(),
          run: (map() -> any()),
          setup: (map() -> map()) | nil,
          teardown: (map() -> :ok) | nil
        }

  @type load_test_opts :: [
          duration: non_neg_integer(),
          concurrency: pos_integer(),
          ramp_up: non_neg_integer(),
          report_interval: non_neg_integer(),
          warmup_duration: non_neg_integer(),
          cooldown_duration: non_neg_integer(),
          telemetry_prefix: [atom()],
          scenario_timeout: non_neg_integer()
        ]

  @type load_test_result :: %{
          start_time: DateTime.t(),
          end_time: DateTime.t(),
          duration_ms: non_neg_integer(),
          total_requests: non_neg_integer(),
          successful_requests: non_neg_integer(),
          failed_requests: non_neg_integer(),
          scenarios: map(),
          metrics: map(),
          errors: [map()]
        }

  @callback scenarios() :: [scenario()]
  @callback setup(map()) :: {:ok, map()} | {:error, term()}
  @callback teardown(map()) :: :ok

  @optional_callbacks [setup: 1, teardown: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Foundation.Telemetry.LoadTest

      def setup(context), do: {:ok, context}
      def teardown(_context), do: :ok

      defoverridable setup: 1, teardown: 1
    end
  end

  @doc """
  Runs a load test using the specified module.

  ## Options

  - `:duration` - Total test duration in milliseconds (required)
  - `:concurrency` - Number of concurrent workers (default: 10)
  - `:ramp_up` - Ramp-up duration in milliseconds (default: 0)
  - `:report_interval` - Progress report interval (default: 5000ms)
  - `:warmup_duration` - Warmup period before recording metrics (default: 0)
  - `:cooldown_duration` - Cooldown period after load (default: 0)
  - `:telemetry_prefix` - Telemetry event prefix (default: [:foundation, :load_test])
  - `:scenario_timeout` - Timeout for individual scenarios (default: 30000ms)
  """
  @spec run(module(), load_test_opts()) :: {:ok, load_test_result()} | {:error, term()}
  def run(load_test_module, opts) do
    # Use a ref-based approach to track PIDs
    pids_ref = :erlang.make_ref()
    Process.put({:load_test_pids, pids_ref}, %{coordinator: nil, collector: nil})

    try do
      with :ok <- validate_opts(opts),
           {:ok, context} <- setup_test(load_test_module, opts),
           {:ok, coordinator} <- start_coordinator(context),
           {:ok, collector} <- start_collector(context) do
        # Store PIDs for cleanup
        Process.put({:load_test_pids, pids_ref}, %{coordinator: coordinator, collector: collector})

        with :ok <- execute_test(coordinator, collector, context),
             {:ok, result} <- generate_report(collector, context) do
          teardown_test(load_test_module, context)
          {:ok, result}
        end
      end
    after
      # Clean up processes if they exist - use shutdown to allow cleanup
      case Process.get({:load_test_pids, pids_ref}) do
        %{coordinator: coordinator, collector: collector} ->
          if is_pid(coordinator) && Process.alive?(coordinator) do
            try do
              GenServer.stop(coordinator, :shutdown, 5000)
            catch
              :exit, _ -> :ok
            end
          end

          if is_pid(collector) && Process.alive?(collector) do
            try do
              GenServer.stop(collector, :shutdown, 5000)
            catch
              :exit, _ -> :ok
            end
          end

        _ ->
          :ok
      end

      Process.delete({:load_test_pids, pids_ref})
    end
  end

  @doc """
  Runs a simple load test with a single scenario function.

  ## Example

      Foundation.Telemetry.LoadTest.run_simple(
        fn _ctx ->
          # Your test code here
          :ok
        end,
        duration: :timer.seconds(30),
        concurrency: 50
      )
  """
  @spec run_simple((map() -> any()), load_test_opts()) ::
          {:ok, load_test_result()} | {:error, term()}
  def run_simple(scenario_fun, opts) when is_function(scenario_fun, 1) do
    # Use ETS to store the function for cross-process access
    table_name = :"load_test_simple_#{:erlang.unique_integer([:positive])}"
    :ets.new(table_name, [:set, :public, :named_table])
    :ets.insert(table_name, {:scenario_fun, scenario_fun})

    # Store table name in process dictionary for SimpleWrapper to access
    Process.put(:simple_scenario_table, table_name)

    try do
      run(Foundation.Telemetry.LoadTest.SimpleWrapper, opts)
    after
      # Clean up ETS table
      :ets.delete(table_name)
    end
  end

  # Private functions

  defp validate_opts(opts) do
    cond do
      !Keyword.has_key?(opts, :duration) ->
        {:error, "duration option is required"}

      opts[:duration] <= 0 ->
        {:error, "duration must be positive"}

      Keyword.get(opts, :concurrency, 10) <= 0 ->
        {:error, "concurrency must be positive"}

      true ->
        :ok
    end
  end

  defp setup_test(module, opts) do
    # Get simple scenario table if it exists
    simple_table = Process.get(:simple_scenario_table)

    scenarios =
      if simple_table do
        get_simple_scenarios(simple_table)
      else
        module.scenarios()
      end

    if Enum.empty?(scenarios) do
      Logger.error("Setup test with empty scenarios! Module: #{inspect(module)}")
    else
      Logger.debug(
        "Setup test with #{length(scenarios)} scenarios: #{inspect(Enum.map(scenarios, & &1.name))}"
      )
    end

    context = %{
      module: module,
      opts: normalize_opts(opts),
      scenarios: scenarios,
      start_time: DateTime.utc_now(),
      test_id: generate_test_id()
    }

    case module.setup(context) do
      {:ok, updated_context} ->
        {:ok, Map.merge(context, updated_context)}

      {:error, _} = error ->
        error
    end
  end

  defp get_simple_scenarios(table_name) do
    case :ets.lookup(table_name, :scenario_fun) do
      [{:scenario_fun, fun}] ->
        [
          %{
            name: :simple_scenario,
            weight: 100,
            run: fun
          }
        ]

      [] ->
        [
          %{
            name: :simple_scenario,
            weight: 100,
            run: fn _ctx -> {:ok, :no_op} end
          }
        ]
    end
  end

  defp normalize_opts(opts) do
    Keyword.merge(
      [
        concurrency: 10,
        ramp_up: 0,
        report_interval: 5000,
        warmup_duration: 0,
        cooldown_duration: 0,
        telemetry_prefix: [:foundation, :load_test],
        scenario_timeout: 30000
      ],
      opts
    )
  end

  defp start_coordinator(context) do
    # Start without linking to avoid test process shutdown
    {:ok, pid} = GenServer.start(Foundation.Telemetry.LoadTest.Coordinator, context)
    {:ok, pid}
  end

  defp start_collector(context) do
    # Start without linking to avoid test process shutdown
    {:ok, pid} = GenServer.start(Foundation.Telemetry.LoadTest.Collector, context)
    {:ok, pid}
  end

  defp execute_test(coordinator, collector, context) do
    opts = context.opts

    # Warmup phase
    if opts[:warmup_duration] > 0 do
      Logger.info("Starting warmup phase (#{opts[:warmup_duration]}ms)")
      Process.send_after(collector, :start_recording, opts[:warmup_duration])
      Process.sleep(opts[:warmup_duration])
    else
      send(collector, {:start_recording, self()})
      # Wait for collector to confirm it's recording
      receive do
        :recording_started -> :ok
      after
        1000 ->
          Logger.error("Collector failed to confirm recording started")
          :ok
      end
    end

    # Start load generation
    Foundation.Telemetry.LoadTest.Coordinator.start_load(coordinator)

    # Monitor progress
    monitor_progress(coordinator, collector, context)

    # Cooldown phase
    if opts[:cooldown_duration] > 0 do
      Logger.info("Starting cooldown phase (#{opts[:cooldown_duration]}ms)")
      Process.sleep(opts[:cooldown_duration])
    end

    # Stop everything
    Foundation.Telemetry.LoadTest.Coordinator.stop_load(coordinator)
    Foundation.Telemetry.LoadTest.Collector.stop_collection(collector)

    :ok
  end

  defp monitor_progress(coordinator, collector, context) do
    report_interval = context.opts[:report_interval]
    end_time = System.monotonic_time(:millisecond) + context.opts[:duration]

    monitor_loop(coordinator, collector, report_interval, end_time)
  end

  defp monitor_loop(coordinator, collector, interval, end_time) do
    now = System.monotonic_time(:millisecond)

    if now < end_time do
      # Get current stats
      stats = Foundation.Telemetry.LoadTest.Collector.get_stats(collector)

      # Log progress
      Logger.info("Load test progress: #{inspect(stats)}")

      # Wait for next interval
      remaining = end_time - now
      Process.sleep(min(interval, remaining))

      monitor_loop(coordinator, collector, interval, end_time)
    end
  end

  defp generate_report(collector, context) do
    Foundation.Telemetry.LoadTest.Collector.generate_report(collector, context)
  end

  defp teardown_test(module, context) do
    module.teardown(context)
  end

  defp generate_test_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end
