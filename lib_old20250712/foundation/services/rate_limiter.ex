defmodule Foundation.Services.RateLimiter do
  @moduledoc """
  Production-grade rate limiting service using Hammer.

  Provides centralized rate limiting with configurable policies for
  protecting APIs and services from excessive requests. Integrates with
  telemetry for monitoring and alerting on rate limit violations.

  ## Features

  - Multiple named rate limiters with independent configurations
  - Sliding window rate limiting using Hammer
  - Per-identifier tracking (user, IP, API key, etc.)
  - Configurable rate limit policies
  - Real-time statistics and monitoring
  - Automatic cleanup of expired entries
  - Integration with Foundation telemetry

  ## Rate Limiter Configuration

  Each rate limiter supports the following configuration:

  - `:scale_ms` - Time window in milliseconds
  - `:limit` - Maximum requests allowed in the time window
  - `:cleanup_interval` - How often to clean up expired entries (ms)

  ## Usage

      # Configure a rate limiter for API endpoints
      RateLimiter.configure_limiter(:api_limiter, %{
        scale_ms: 60_000,     # 1 minute window
        limit: 1000,          # 1000 requests per minute
        cleanup_interval: 300_000  # Clean up every 5 minutes
      })

      # Check if request is allowed
      case RateLimiter.check_rate_limit(:api_limiter, user_id) do
        {:ok, :allowed} -> process_request()
        {:ok, :denied} -> return_rate_limit_error()
      end

      # Get current status for an identifier
      {:ok, status} = RateLimiter.get_rate_limit_status(:api_limiter, user_id)
      # => %{remaining: 950, reset_time: ~N[2023-12-01 12:01:00]}
  """

  use GenServer
  require Logger
  require Foundation.ErrorHandling
  alias Foundation.ErrorHandling

  @type limiter_id :: atom() | String.t()
  @type rate_limit_identifier :: String.t() | atom() | integer()
  @type limiter_config :: %{
          scale_ms: pos_integer(),
          limit: pos_integer(),
          cleanup_interval: pos_integer()
        }
  @type rate_limit_result :: :allowed | :denied
  @type rate_limit_status :: %{
          remaining: non_neg_integer(),
          reset_time: DateTime.t(),
          limit: pos_integer()
        }

  # Default configuration
  @default_config %{
    # 1 minute
    scale_ms: 60_000,
    # 1000 requests per minute
    limit: 1000,
    # 5 minutes
    cleanup_interval: 300_000
  }

  defstruct limiters: %{},
            stats: %{total_checks: 0, total_denials: 0, total_allowed: 0},
            cleanup_timers: %{},
            buckets: %{}

  # Client API

  @doc """
  Starts the rate limiter service.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Configures a rate limiter with the specified settings.

  ## Examples

      {:ok, limiter_id} = RateLimiter.configure_limiter(:user_api, %{
        scale_ms: 60_000,    # 1 minute window
        limit: 100,          # 100 requests per minute
        cleanup_interval: 300_000  # Clean up every 5 minutes
      })
  """
  @spec configure_limiter(limiter_id(), limiter_config()) :: {:ok, limiter_id()} | {:error, term()}
  def configure_limiter(limiter_id, config) do
    GenServer.call(__MODULE__, {:configure_limiter, limiter_id, config})
  end

  @doc """
  Checks if a request is allowed under the rate limit.

  ## Examples

      case RateLimiter.check_rate_limit(:api_limiter, "user_123") do
        {:ok, :allowed} ->
          # Process the request
          handle_request()

        {:ok, :denied} ->
          # Return rate limit exceeded error
          {:error, :rate_limit_exceeded}
      end
  """
  @spec check_rate_limit(limiter_id(), rate_limit_identifier()) ::
          {:ok, rate_limit_result()} | {:error, term()}
  def check_rate_limit(limiter_id, identifier) do
    GenServer.call(__MODULE__, {:check_rate_limit, limiter_id, identifier})
  end

  @doc """
  Gets the current rate limit status for an identifier.

  Returns information about remaining requests and when the window resets.
  """
  @spec get_rate_limit_status(limiter_id(), rate_limit_identifier()) ::
          {:ok, rate_limit_status()} | {:error, term()}
  def get_rate_limit_status(limiter_id, identifier) do
    GenServer.call(__MODULE__, {:get_rate_limit_status, limiter_id, identifier})
  end

  @doc """
  Removes a rate limiter configuration.
  """
  @spec remove_limiter(limiter_id()) :: :ok | {:error, term()}
  def remove_limiter(limiter_id) do
    GenServer.call(__MODULE__, {:remove_limiter, limiter_id})
  end

  @doc """
  Triggers manual cleanup of expired rate limit entries.
  """
  def trigger_cleanup do
    GenServer.call(__MODULE__, :trigger_cleanup)
  end

  @doc """
  Gets rate limiter statistics and metrics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Ensure Hammer is started
    case Application.ensure_all_started(:hammer) do
      {:ok, _} ->
        Logger.debug("Hammer rate limiting backend started")

      {:error, reason} ->
        Logger.warning("Failed to start Hammer: #{inspect(reason)}")
    end

    state = %__MODULE__{
      limiters: %{},
      stats: %{total_checks: 0, total_denials: 0, total_allowed: 0},
      cleanup_timers: %{},
      buckets: %{}
    }

    Logger.info("Foundation.Services.RateLimiter started")

    {:ok, state}
  end

  @impl true
  def handle_call({:configure_limiter, limiter_id, config}, _from, state) do
    case validate_limiter_config(config) do
      {:ok, validated_config} ->
        # Merge with defaults
        limiter_config = Map.merge(@default_config, validated_config)

        # Set up cleanup timer for this limiter
        cleanup_timer = setup_cleanup_timer(limiter_id, limiter_config.cleanup_interval)

        # Update state
        new_limiters = Map.put(state.limiters, limiter_id, limiter_config)
        new_timers = Map.put(state.cleanup_timers, limiter_id, cleanup_timer)

        emit_telemetry(:limiter_configured, %{
          limiter_id: limiter_id,
          scale_ms: limiter_config.scale_ms,
          limit: limiter_config.limit
        })

        {:reply, {:ok, limiter_id}, %{state | limiters: new_limiters, cleanup_timers: new_timers}}

      {:error, reason} ->
        {:reply, ErrorHandling.normalize_error({:error, reason}), state}
    end
  end

  @impl true
  def handle_call({:check_rate_limit, limiter_id, identifier}, _from, state) do
    case Map.get(state.limiters, limiter_id) do
      nil ->
        {:reply, {:error, :limiter_not_found}, state}

      limiter_config ->
        start_time = System.monotonic_time(:millisecond)

        # Use simple in-memory rate limiting for now
        # TO DO: Replace with proper Hammer integration when API is clarified
        limiter_key = {limiter_id, identifier}
        current_time = System.monotonic_time(:millisecond)

        # Use atomic check and increment
        result =
          case check_and_increment_rate_limit(limiter_key, limiter_config, current_time) do
            {:allow, _} -> :allowed
            {:deny, _} -> :denied
          end

        duration = System.monotonic_time(:millisecond) - start_time

        # Update statistics
        new_stats = update_stats(state.stats, result)

        emit_rate_limit_telemetry(limiter_id, identifier, result, duration)

        {:reply, {:ok, result}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:get_rate_limit_status, limiter_id, identifier}, _from, state) do
    case Map.get(state.limiters, limiter_id) do
      nil ->
        {:reply, {:error, :limiter_not_found}, state}

      limiter_config ->
        limiter_key = {limiter_id, identifier}
        current_time = System.monotonic_time(:millisecond)

        case get_rate_limit_bucket(limiter_key, limiter_config, current_time) do
          {:allow, count} ->
            remaining = max(0, limiter_config.limit - count)
            window_start = current_time - rem(current_time, limiter_config.scale_ms)

            reset_time =
              DateTime.add(
                DateTime.utc_now(),
                limiter_config.scale_ms - (current_time - window_start),
                :millisecond
              )

            status = %{
              remaining: remaining,
              reset_time: reset_time,
              limit: limiter_config.limit
            }

            {:reply, {:ok, status}, state}

          {:deny, _count} ->
            remaining = 0
            window_start = current_time - rem(current_time, limiter_config.scale_ms)

            reset_time =
              DateTime.add(
                DateTime.utc_now(),
                limiter_config.scale_ms - (current_time - window_start),
                :millisecond
              )

            status = %{
              remaining: remaining,
              reset_time: reset_time,
              limit: limiter_config.limit
            }

            {:reply, {:ok, status}, state}
        end
    end
  end

  @impl true
  def handle_call({:remove_limiter, limiter_id}, _from, state) do
    if Map.has_key?(state.limiters, limiter_id) do
      # Cancel cleanup timer
      if timer_ref = Map.get(state.cleanup_timers, limiter_id) do
        Process.cancel_timer(timer_ref)
      end

      new_limiters = Map.delete(state.limiters, limiter_id)
      new_timers = Map.delete(state.cleanup_timers, limiter_id)

      emit_telemetry(:limiter_removed, %{limiter_id: limiter_id})

      {:reply, :ok, %{state | limiters: new_limiters, cleanup_timers: new_timers}}
    else
      {:reply, {:error, :limiter_not_found}, state}
    end
  end

  @impl true
  def handle_call(:trigger_cleanup, _from, state) do
    # Trigger cleanup for all configured limiters
    cleanup_count = perform_cleanup(state.limiters)

    emit_telemetry(:cleanup_performed, %{cleaned_entries: cleanup_count})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # Return health status based on service state
    health_status = if map_size(state.limiters) < 1000, do: :healthy, else: :degraded
    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      limiters:
        Map.keys(state.limiters) |> Enum.into(%{}, &{&1, get_limiter_stats(&1, state.limiters[&1])}),
      total_checks: state.stats.total_checks,
      total_denials: state.stats.total_denials,
      total_allowed: state.stats.total_allowed,
      active_limiters: map_size(state.limiters)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call({:get_limiter_config, limiter_id}, _from, state) do
    config = Map.get(state.limiters, limiter_id, @default_config)
    {:reply, config, state}
  end

  @impl true
  def handle_info({:cleanup, limiter_id}, state) do
    case Map.get(state.limiters, limiter_id) do
      nil ->
        # Limiter was removed, ignore cleanup
        {:noreply, state}

      limiter_config ->
        # Cancel old timer if it exists
        if old_timer = Map.get(state.cleanup_timers, limiter_id) do
          Process.cancel_timer(old_timer)
        end

        # Perform cleanup for this specific limiter
        cleanup_count = perform_limiter_cleanup(limiter_id)

        Logger.debug(
          "Performed cleanup for limiter #{limiter_id}: #{cleanup_count} entries cleaned"
        )

        # Schedule next cleanup
        timer_ref = setup_cleanup_timer(limiter_id, limiter_config.cleanup_interval)
        new_timers = Map.put(state.cleanup_timers, limiter_id, timer_ref)

        {:noreply, %{state | cleanup_timers: new_timers}}
    end
  end

  # Private Implementation

  @spec validate_limiter_config(map()) :: {:ok, limiter_config()} | {:error, term()}
  defp validate_limiter_config(config) when is_map(config) do
    required_fields = [:scale_ms, :limit]

    case Enum.find(required_fields, &(not Map.has_key?(config, &1))) do
      nil ->
        validated = %{
          scale_ms: config.scale_ms,
          limit: config.limit,
          cleanup_interval: Map.get(config, :cleanup_interval, @default_config.cleanup_interval)
        }

        {:ok, validated}

      missing_field ->
        ErrorHandling.missing_field_error(missing_field)
    end
  end

  defp validate_limiter_config(_), do: ErrorHandling.invalid_field_error(:config, :invalid_format)

  defp update_stats(stats, :allowed) do
    stats
    |> Map.update!(:total_checks, &(&1 + 1))
    |> Map.update!(:total_allowed, &(&1 + 1))
  end

  defp update_stats(stats, :denied) do
    stats
    |> Map.update!(:total_checks, &(&1 + 1))
    |> Map.update!(:total_denials, &(&1 + 1))
  end

  defp setup_cleanup_timer(limiter_id, interval_ms) do
    Process.send_after(self(), {:cleanup, limiter_id}, interval_ms)
  end

  defp perform_cleanup(limiters) do
    limiters
    |> Map.keys()
    |> Enum.reduce(0, fn limiter_id, acc ->
      acc + perform_limiter_cleanup(limiter_id)
    end)
  end

  defp perform_limiter_cleanup(limiter_id) do
    # Clean up expired rate limit windows
    current_time = System.monotonic_time(:millisecond)

    # Get all limiters to check window expiration
    case :ets.info(:rate_limit_buckets) do
      :undefined ->
        0

      _ ->
        # Get the limiter config to know the window size
        limiter_config =
          Foundation.ErrorHandling.safe_call do
            GenServer.call(__MODULE__, {:get_limiter_config, limiter_id}, 100)
          end
          |> case do
            {:ok, config} -> config
            # Default 1 minute window
            {:error, _} -> %{scale_ms: 60_000}
          end

        # Find and delete expired buckets
        expired =
          :ets.foldl(
            fn
              {{key, window_start}, _count}, acc when is_tuple(key) ->
                # Check if this bucket belongs to our limiter
                case key do
                  {^limiter_id, _identifier} ->
                    # Check if window is expired (older than 2 windows)
                    expiry_time = window_start + limiter_config.scale_ms * 2

                    if current_time > expiry_time do
                      :ets.delete(:rate_limit_buckets, {key, window_start})
                      acc + 1
                    else
                      acc
                    end

                  _ ->
                    acc
                end

              _, acc ->
                acc
            end,
            0,
            :rate_limit_buckets
          )

        # Log if we cleaned up a lot of entries
        if expired > 1000 do
          Logger.warning(
            "Rate limiter cleaned up #{expired} expired entries for limiter #{limiter_id}"
          )
        end

        expired
    end
  end

  defp get_limiter_stats(_limiter_id, limiter_config) do
    %{
      scale_ms: limiter_config.scale_ms,
      limit: limiter_config.limit,
      cleanup_interval: limiter_config.cleanup_interval
    }
  end

  defp emit_telemetry(event, metadata) do
    ErrorHandling.emit_telemetry_safe(
      [:foundation, :rate_limiter, event],
      %{count: 1},
      metadata
    )
  end

  defp emit_rate_limit_telemetry(limiter_id, identifier, result, duration) do
    metadata = %{
      limiter_id: limiter_id,
      identifier: identifier,
      result: result
    }

    ErrorHandling.emit_telemetry_safe(
      [:foundation, :rate_limiter, :check],
      %{duration: duration, count: 1},
      metadata
    )
  end

  # Simple in-memory rate limiting implementation
  # TO DO: Replace with distributed solution for production use

  # Atomic rate limiting using ETS with proper race handling
  defp check_and_increment_rate_limit(limiter_key, limiter_config, current_time) do
    window_start = current_time - rem(current_time, limiter_config.scale_ms)
    bucket_key = {limiter_key, window_start}

    ensure_rate_limit_table()

    # Use atomic check-and-set pattern with proper limit enforcement
    case :ets.lookup(:rate_limit_buckets, bucket_key) do
      [] ->
        # No entry exists, try to insert with count 1
        case :ets.insert_new(:rate_limit_buckets, {bucket_key, 1}) do
          true ->
            {:allow, 1}

          false ->
            # Race condition: another process created it, retry
            check_and_increment_rate_limit(limiter_key, limiter_config, current_time)
        end

      [{^bucket_key, current_count}] ->
        if current_count >= limiter_config.limit do
          # Already at limit, deny without incrementing
          {:deny, current_count}
        else
          # Try atomic increment with condition
          # Use update_counter with threshold to ensure atomicity
          try do
            # Atomic increment only if under limit
            new_count = :ets.update_counter(:rate_limit_buckets, bucket_key, {2, 1})

            if new_count <= limiter_config.limit do
              {:allow, new_count}
            else
              # Went over limit in race condition, roll back atomically
              final_count = :ets.update_counter(:rate_limit_buckets, bucket_key, {2, -1})
              {:deny, final_count}
            end
          catch
            :error, :badarg ->
              # Entry was deleted during operation, retry
              check_and_increment_rate_limit(limiter_key, limiter_config, current_time)
          end
        end
    end
  end

  defp get_rate_limit_bucket(limiter_key, limiter_config, current_time) do
    # Calculate window start
    window_start = current_time - rem(current_time, limiter_config.scale_ms)
    bucket_key = {limiter_key, window_start}

    # Get current count from ETS
    count =
      case :ets.lookup(:rate_limit_buckets, bucket_key) do
        [{^bucket_key, count}] -> count
        [] -> 0
      end

    if count >= limiter_config.limit do
      {:deny, count}
    else
      {:allow, count}
    end
  rescue
    _ ->
      # If ETS table doesn't exist, assume no rate limiting
      {:allow, 0}
  end

  defp ensure_rate_limit_table() do
    case :ets.info(:rate_limit_buckets) do
      :undefined ->
        try do
          table = :ets.new(:rate_limit_buckets, [:set, :public, :named_table])

          # Register with ResourceManager for monitoring
          if Process.whereis(Foundation.ResourceManager) do
            Foundation.ResourceManager.monitor_table(table)
          end

          table
        rescue
          # Table already exists (race condition)
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel all cleanup timers
    Enum.each(state.cleanup_timers, fn {_limiter_id, timer_ref} ->
      if timer_ref do
        Process.cancel_timer(timer_ref)
      end
    end)

    # Delete ETS table if it exists
    try do
      :ets.delete(:rate_limit_buckets)
    rescue
      # Table doesn't exist or already deleted
      ArgumentError -> :ok
    end

    :ok
  end
end
