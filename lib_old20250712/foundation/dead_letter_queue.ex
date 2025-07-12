defmodule Foundation.DeadLetterQueue do
  @moduledoc """
  Handles messages that couldn't be delivered through supervised send.
  Provides retry mechanisms and observability for failed messages.
  """

  use GenServer
  require Logger

  @table :dead_letter_queue
  @max_retries 5
  @retry_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_message(recipient, message, reason, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:add_message, recipient, message, reason, metadata})
  end

  def retry_messages(filter \\ :all) do
    GenServer.call(__MODULE__, {:retry_messages, filter})
  end

  def list_messages(limit \\ 100) do
    GenServer.call(__MODULE__, {:list_messages, limit})
  end

  def purge_messages(filter \\ :all) do
    GenServer.call(__MODULE__, {:purge_messages, filter})
  end

  # Server implementation

  @impl true
  def init(_opts) do
    # Create ETS table for dead letters
    :ets.new(@table, [:set, :named_table, :public])

    # Schedule periodic retry
    schedule_retry()

    {:ok, %{retry_timer: nil}}
  end

  @impl true
  def handle_cast({:add_message, recipient, message, reason, metadata}, state) do
    entry = %{
      id: System.unique_integer([:positive]),
      recipient: recipient,
      message: message,
      reason: reason,
      metadata: metadata,
      attempts: 0,
      first_failure: DateTime.utc_now(),
      last_attempt: DateTime.utc_now()
    }

    :ets.insert(@table, {entry.id, entry})

    :telemetry.execute(
      [:foundation, :dead_letter_queue, :message_added],
      %{count: 1},
      %{reason: reason}
    )

    Logger.info("Message added to dead letter queue",
      recipient: inspect(recipient),
      reason: inspect(reason),
      id: entry.id
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:retry_messages, filter}, state) do
    messages = get_messages_for_retry(filter)

    results =
      Enum.map(messages, fn {id, entry} ->
        case retry_message(entry) do
          :ok ->
            :ets.delete(@table, id)
            {:ok, id}

          {:error, reason} ->
            update_retry_attempt(id, entry)
            {:error, id, reason}
        end
      end)

    # Notify test completion if in test mode
    maybe_notify_test_completion({:retry_completed, filter, results})

    {:noreply, state}
  end

  @impl true
  def handle_call({:retry_messages, filter}, _from, state) do
    messages = get_messages_for_retry(filter)

    results =
      Enum.map(messages, fn {id, entry} ->
        case retry_message(entry) do
          :ok ->
            :ets.delete(@table, id)
            {:ok, id}

          {:error, reason} ->
            update_retry_attempt(id, entry)
            {:error, id, reason}
        end
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:list_messages, limit}, _from, state) do
    messages =
      :ets.tab2list(@table)
      |> Enum.take(limit)
      |> Enum.map(fn {_id, entry} -> entry end)

    {:reply, messages, state}
  end

  @impl true
  def handle_call({:purge_messages, filter}, _from, state) do
    messages_to_purge = get_messages_for_purge(filter)

    count =
      Enum.reduce(messages_to_purge, 0, fn {id, _entry}, acc ->
        :ets.delete(@table, id)
        acc + 1
      end)

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_info(:retry_tick, state) do
    # Retry old messages (use cast to avoid calling ourselves)
    GenServer.cast(__MODULE__, {:retry_messages, :auto})

    # Schedule next retry
    schedule_retry()

    {:noreply, state}
  end

  @impl true
  def handle_info(_unexpected_message, state) do
    # Ignore unexpected messages
    {:noreply, state}
  end

  defp retry_message(%{recipient: recipient, message: message, attempts: attempts}) do
    if attempts < @max_retries do
      Foundation.SupervisedSend.send_supervised(recipient, message,
        timeout: 10_000,
        retries: 2,
        # Don't re-add to dead letter
        on_error: :ignore
      )
    else
      {:error, :max_retries_exceeded}
    end
  end

  defp update_retry_attempt(id, entry) do
    updated = %{entry | attempts: entry.attempts + 1, last_attempt: DateTime.utc_now()}
    :ets.insert(@table, {id, updated})
  end

  defp get_messages_for_retry(:all) do
    :ets.tab2list(@table)
  end

  defp get_messages_for_retry(:auto) do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, entry} ->
      DateTime.diff(now, entry.last_attempt, :second) > 300 and
        entry.attempts < @max_retries
    end)
  end

  defp get_messages_for_purge(:all) do
    :ets.tab2list(@table)
  end

  defp get_messages_for_purge(:expired) do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, entry} ->
      entry.attempts >= @max_retries or
        DateTime.diff(now, entry.first_failure, :hour) > 24
    end)
  end

  defp schedule_retry do
    Process.send_after(self(), :retry_tick, @retry_interval)
  end

  # Test notification helper - zero overhead in production
  defp maybe_notify_test_completion(message) do
    case Application.get_env(:foundation, :test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end
end
