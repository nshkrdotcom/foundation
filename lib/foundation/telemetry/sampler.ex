defmodule Foundation.Telemetry.Sampler do
  @moduledoc """
  Telemetry event sampling for high-volume scenarios.

  This module provides sampling strategies to reduce telemetry overhead in
  high-throughput systems while maintaining statistical accuracy.

  ## Features

  - Multiple sampling strategies (random, rate-based, adaptive)
  - Per-event type configuration
  - Automatic rate limiting
  - Statistical sampling with configurable confidence
  - Dynamic adjustment based on system load

  ## Usage

      # Configure sampling in your application
      config :foundation, :telemetry_sampling,
        enabled: true,
        default_strategy: :random,
        default_rate: 0.1,  # Sample 10% by default
        
        event_configs: [
          {[:foundation, :cache, :get, :stop], strategy: :random, rate: 0.01},  # 1% for high-volume
          {[:foundation, :span, :stop], strategy: :adaptive, target_rate: 1000},  # Max 1000/sec
          {[:foundation, :load_test, :scenario, :stop], strategy: :rate_limited, max_per_second: 5000}
        ]
      
      # Or configure at runtime
      Foundation.Telemetry.Sampler.configure_event(
        [:my_app, :high_volume, :event],
        strategy: :random,
        rate: 0.05
      )
  """

  use GenServer
  require Logger

  @type strategy :: :always | :never | :random | :rate_limited | :adaptive | :reservoir

  @type event_config :: %{
          event: [atom()],
          strategy: strategy(),
          rate: float(),
          max_per_second: non_neg_integer(),
          reservoir_size: non_neg_integer(),
          adaptive_config: map()
        }

  defmodule State do
    @moduledoc false
    defstruct [
      :enabled,
      :default_strategy,
      :default_rate,
      :event_configs,
      :event_counters,
      :rate_limiters,
      :reservoirs,
      :last_reset
    ]
  end

  # Client API

  @doc """
  Starts the telemetry sampler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Determines if an event should be sampled.

  ## Examples

      if Foundation.Telemetry.Sampler.should_sample?([:my_app, :event], metadata) do
        :telemetry.execute([:my_app, :event], measurements, metadata)
      end
  """
  @spec should_sample?([atom()], map()) :: boolean()
  def should_sample?(event, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:should_sample?, event, metadata})
  catch
    :exit, _ ->
      # If sampler is not running, always sample
      true
  end

  @doc """
  Configures sampling for a specific event at runtime.
  """
  @spec configure_event([atom()], keyword()) :: :ok
  def configure_event(event, opts) do
    GenServer.call(__MODULE__, {:configure_event, event, opts})
  end

  @doc """
  Gets current sampling statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Resets sampling statistics.
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  @doc """
  Wraps telemetry execute with sampling.

  ## Example

      Foundation.Telemetry.Sampler.execute(
        [:my_app, :event],
        %{duration: 100},
        %{user_id: 123}
      )
  """
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements, metadata) do
    if should_sample?(event, metadata) do
      # Add sampling metadata
      enhanced_metadata = Map.put(metadata, :sampled, true)
      :telemetry.execute(event, measurements, enhanced_metadata)
    end

    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    config = Application.get_env(:foundation, :telemetry_sampling, [])

    state = %State{
      enabled: Keyword.get(config, :enabled, false),
      default_strategy: Keyword.get(config, :default_strategy, :always),
      default_rate: Keyword.get(config, :default_rate, 1.0),
      event_configs: build_event_configs(Keyword.get(config, :event_configs, [])),
      event_counters: %{},
      rate_limiters: %{},
      reservoirs: %{},
      last_reset: System.monotonic_time(:second)
    }

    # Schedule periodic reset
    if state.enabled do
      schedule_reset()
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:should_sample?, event, metadata}, _from, state) do
    if state.enabled do
      config = get_event_config(event, state)
      should_sample = apply_sampling_strategy(event, metadata, config, state)

      # Update counters
      new_state = update_counters(event, should_sample, state)

      {:reply, should_sample, new_state}
    else
      {:reply, true, state}
    end
  end

  @impl true
  def handle_call({:configure_event, event, opts}, _from, state) do
    config = build_single_event_config({event, opts})
    new_configs = Map.put(state.event_configs, event, config)

    {:reply, :ok, %{state | event_configs: new_configs}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      event_stats: format_event_stats(state),
      uptime_seconds: System.monotonic_time(:second) - state.last_reset
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    new_state = %{
      state
      | event_counters: %{},
        rate_limiters: %{},
        reservoirs: %{},
        last_reset: System.monotonic_time(:second)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:reset_rate_limiters, state) do
    # Reset rate limiter windows
    new_rate_limiters =
      Map.new(state.rate_limiters, fn {event, _} ->
        {event, %{count: 0, window_start: System.monotonic_time(:millisecond)}}
      end)

    schedule_reset()

    {:noreply, %{state | rate_limiters: new_rate_limiters}}
  end

  # Private functions

  defp build_event_configs(configs) do
    configs
    |> Enum.map(&build_single_event_config/1)
    |> Map.new(fn config -> {config.event, config} end)
  end

  defp build_single_event_config({event, opts}) do
    %{
      event: event,
      strategy: Keyword.get(opts, :strategy, :random),
      rate: Keyword.get(opts, :rate, 1.0),
      max_per_second: Keyword.get(opts, :max_per_second, 10_000),
      reservoir_size: Keyword.get(opts, :reservoir_size, 1000),
      adaptive_config:
        Keyword.get(opts, :adaptive_config, %{
          target_rate: 1000,
          adjustment_interval: 5000,
          increase_factor: 1.1,
          decrease_factor: 0.9
        })
    }
  end

  defp get_event_config(event, state) do
    case Map.get(state.event_configs, event) do
      nil ->
        # Use default config
        %{
          event: event,
          strategy: state.default_strategy,
          rate: state.default_rate,
          max_per_second: 10_000,
          reservoir_size: 1000,
          adaptive_config: %{}
        }

      config ->
        config
    end
  end

  defp apply_sampling_strategy(event, metadata, config, state) do
    case config.strategy do
      :always ->
        true

      :never ->
        false

      :random ->
        :rand.uniform() < config.rate

      :rate_limited ->
        check_rate_limit(event, config, state)

      :adaptive ->
        check_adaptive_sampling(event, metadata, config, state)

      :reservoir ->
        check_reservoir_sampling(event, config, state)

      strategy ->
        Logger.warning("Unknown sampling strategy: #{inspect(strategy)}, defaulting to always")
        true
    end
  end

  defp check_rate_limit(event, config, state) do
    now = System.monotonic_time(:millisecond)

    limiter =
      Map.get(state.rate_limiters, event, %{
        count: 0,
        window_start: now
      })

    # Check if we need to reset the window (1 second windows)
    if now - limiter.window_start >= 1000 do
      # New window, allow
      true
    else
      # Within window, check count
      limiter.count < config.max_per_second
    end
  end

  defp check_adaptive_sampling(event, _metadata, config, state) do
    # Get current rate
    counter = Map.get(state.event_counters, event, %{sampled: 0, total: 0})

    if counter.total == 0 do
      # No data yet, use default rate
      :rand.uniform() < config.rate
    else
      # Calculate current sampling rate
      current_rate = counter.sampled / counter.total

      # Adjust based on target rate
      target_per_second = config.adaptive_config.target_rate

      current_per_second =
        counter.sampled / max(1, System.monotonic_time(:second) - state.last_reset)

      adjusted_rate =
        if current_per_second > target_per_second do
          # Decrease sampling
          current_rate * config.adaptive_config.decrease_factor
        else
          # Increase sampling
          min(1.0, current_rate * config.adaptive_config.increase_factor)
        end

      :rand.uniform() < adjusted_rate
    end
  end

  defp check_reservoir_sampling(event, config, state) do
    # Reservoir sampling for fixed-size sample
    counter = Map.get(state.event_counters, event, %{total: 0})

    if counter.total < config.reservoir_size do
      # Haven't filled reservoir yet
      true
    else
      # Probability of inclusion decreases with total count
      :rand.uniform(counter.total + 1) <= config.reservoir_size
    end
  end

  defp update_counters(event, sampled, state) do
    counter = Map.get(state.event_counters, event, %{sampled: 0, total: 0})

    updated_counter = %{
      sampled: if(sampled, do: counter.sampled + 1, else: counter.sampled),
      total: counter.total + 1
    }

    new_counters = Map.put(state.event_counters, event, updated_counter)

    # Update rate limiter if needed
    new_rate_limiters =
      if sampled do
        update_rate_limiter(event, state.rate_limiters)
      else
        state.rate_limiters
      end

    %{state | event_counters: new_counters, rate_limiters: new_rate_limiters}
  end

  defp update_rate_limiter(event, rate_limiters) do
    now = System.monotonic_time(:millisecond)

    limiter =
      Map.get(rate_limiters, event, %{
        count: 0,
        window_start: now
      })

    updated_limiter =
      if now - limiter.window_start >= 1000 do
        # New window
        %{count: 1, window_start: now}
      else
        # Same window
        %{limiter | count: limiter.count + 1}
      end

    Map.put(rate_limiters, event, updated_limiter)
  end

  defp format_event_stats(state) do
    Map.new(state.event_counters, fn {event, counter} ->
      sampling_rate =
        if counter.total > 0 do
          Float.round(counter.sampled / counter.total * 100, 2)
        else
          0.0
        end

      {event,
       %{
         sampled: counter.sampled,
         total: counter.total,
         sampling_rate_percent: sampling_rate,
         strategy: get_event_config(event, state).strategy
       }}
    end)
  end

  defp schedule_reset do
    # Reset rate limiters every second
    Process.send_after(self(), :reset_rate_limiters, 1000)
  end
end
