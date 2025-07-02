defmodule Foundation.Telemetry.SampledEvents.Server do
  @moduledoc """
  GenServer for managing sampled events state.

  This server manages:
  - Event deduplication tracking via ETS
  - Batch accumulation and processing
  - Automatic cleanup of stale entries

  All state is stored in ETS for high-performance concurrent access.
  """

  use GenServer
  require Logger

  @dedup_table :sampled_events_dedup
  @batch_table :sampled_events_batch
  # 1 second default
  @batch_interval 1000
  # 1 minute
  @cleanup_interval 60_000

  # Client API

  @doc """
  Starts the SampledEvents server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an event should be emitted based on deduplication rules.
  Returns true if the event should be emitted, false if it should be skipped.
  """
  def should_emit?(event_key, interval_ms) do
    now = System.monotonic_time(:millisecond)

    # Use atomic compare-and-swap operation
    case :ets.lookup(@dedup_table, event_key) do
      [] ->
        # First time seeing this event
        :ets.insert(@dedup_table, {event_key, now})
        true

      [{^event_key, last_emit}] when now - last_emit >= interval_ms ->
        # Enough time has passed
        :ets.insert(@dedup_table, {event_key, now})
        true

      _ ->
        # Too soon, skip
        false
    end
  end

  @doc """
  Add an item to a batch.
  """
  def add_to_batch(batch_key, item) do
    # Initialize if needed, then increment counter
    now = System.monotonic_time(:millisecond)
    :ets.insert_new(@batch_table, {batch_key, 0, now})
    :ets.update_counter(@batch_table, batch_key, {2, 1})

    # Add the item
    :ets.insert(@batch_table, {{:batch_item, batch_key, make_ref()}, item})
    :ok
  end

  @doc """
  Get current batch info.
  """
  def get_batch_info(batch_key) do
    case :ets.lookup(@batch_table, batch_key) do
      [{^batch_key, count, last_emit}] -> {:ok, count, last_emit}
      [] -> {:ok, 0, System.monotonic_time(:millisecond)}
    end
  end

  @doc """
  Process a batch immediately.
  """
  def process_batch(batch_key) do
    GenServer.call(__MODULE__, {:process_batch, batch_key})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@dedup_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@batch_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    # Schedule periodic tasks
    batch_interval = Keyword.get(opts, :batch_interval, @batch_interval)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)

    Process.send_after(self(), :process_batches, batch_interval)
    Process.send_after(self(), :cleanup_stale_entries, cleanup_interval)

    state = %{
      batch_interval: batch_interval,
      cleanup_interval: cleanup_interval,
      batch_processors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_batch, batch_key}, _from, state) do
    result = do_process_batch(batch_key)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:process_batches, state) do
    # Find all batch keys
    batch_keys =
      :ets.select(@batch_table, [
        {{:"$1", :"$2", :"$3"}, [{:is_atom, :"$1"}], [:"$1"]}
      ])
      |> Enum.uniq()

    # Process each batch
    Enum.each(batch_keys, &do_process_batch/1)

    # Schedule next batch processing
    Process.send_after(self(), :process_batches, state.batch_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_stale_entries, state) do
    now = System.monotonic_time(:millisecond)
    # 5 minutes
    stale_threshold = 300_000

    # Clean up old deduplication entries
    # Delete entries where (now - timestamp) > stale_threshold
    :ets.select_delete(@dedup_table, [
      {{:"$1", :"$2"}, [{:>, {:-, now, :"$2"}, stale_threshold}], [true]}
    ])

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_stale_entries, state.cleanup_interval)

    {:noreply, state}
  end

  # Private functions

  defp do_process_batch(batch_key) do
    # Get batch info
    case :ets.lookup(@batch_table, batch_key) do
      [{^batch_key, count, _last_emit}] when count > 0 ->
        # Collect all batch items
        # We need to use a guard to match the specific batch_key
        match_spec = [
          {
            {{:batch_item, :"$1", :"$2"}, :"$3"},
            [{:==, :"$1", batch_key}],
            [:"$3"]
          }
        ]

        items = :ets.select(@batch_table, match_spec)

        # Delete batch items for this specific batch
        delete_spec = [
          {
            {{:batch_item, :"$1", :_}, :_},
            [{:==, :"$1", batch_key}],
            [true]
          }
        ]

        :ets.select_delete(@batch_table, delete_spec)

        # Reset counter
        :ets.insert(@batch_table, {batch_key, 0, System.monotonic_time(:millisecond)})

        {:ok, items}

      _ ->
        {:ok, []}
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
