defmodule Foundation.Telemetry.SpanManager do
  @moduledoc """
  GenServer that manages span context storage using ETS.

  This module replaces the Process dictionary usage in span tracking with
  a centralized ETS-based solution that provides:

  - Per-process span stack management
  - Automatic cleanup when processes die
  - Better observability and debugging
  - Compliance with OTP principles
  """

  use GenServer
  require Logger

  @table_name :foundation_span_contexts
  @monitor_table :foundation_span_monitors

  # Client API

  @doc """
  Starts the SpanManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the span stack for the calling process.
  """
  def get_stack(pid \\ self()) do
    case :ets.lookup(@table_name, pid) do
      [{^pid, stack}] -> stack
      [] -> []
    end
  catch
    :error, :badarg -> []
  end

  @doc """
  Sets the span stack for the calling process.
  """
  def set_stack(stack, pid \\ self()) do
    GenServer.call(__MODULE__, {:set_stack, pid, stack})
  end

  @doc """
  Pushes a span onto the stack for the calling process.
  """
  def push_span(span, pid \\ self()) do
    GenServer.call(__MODULE__, {:push_span, pid, span})
  end

  @doc """
  Pops a span from the stack for the calling process.
  """
  def pop_span(pid \\ self()) do
    GenServer.call(__MODULE__, {:pop_span, pid})
  end

  @doc """
  Updates the top span on the stack for the calling process.
  """
  def update_top_span(update_fn, pid \\ self()) do
    GenServer.call(__MODULE__, {:update_top_span, pid, update_fn})
  end

  @doc """
  Clears the span stack for a process.
  """
  def clear_stack(pid \\ self()) do
    GenServer.call(__MODULE__, {:clear_stack, pid})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for span contexts and monitor refs
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@monitor_table, [:named_table, :private, :set])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:set_stack, pid, stack}, _from, state) do
    case stack do
      [] ->
        # Empty stack, clean up
        cleanup_process(pid)
        {:reply, :ok, state}

      _ ->
        # Non-empty stack, ensure monitoring
        ensure_monitored(pid)
        :ets.insert(@table_name, {pid, stack})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:push_span, pid, span}, _from, state) do
    ensure_monitored(pid)
    current_stack = get_stack(pid)
    :ets.insert(@table_name, {pid, [span | current_stack]})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:pop_span, pid}, _from, state) do
    case get_stack(pid) do
      [] ->
        {:reply, nil, state}

      [span | rest] ->
        if rest == [] do
          cleanup_process(pid)
        else
          :ets.insert(@table_name, {pid, rest})
        end

        {:reply, span, state}
    end
  end

  @impl true
  def handle_call({:update_top_span, pid, update_fn}, _from, state) do
    case get_stack(pid) do
      [] ->
        {:reply, :error, state}

      [span | rest] ->
        updated_span = update_fn.(span)
        :ets.insert(@table_name, {pid, [updated_span | rest]})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:clear_stack, pid}, _from, state) do
    cleanup_process(pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # Process died, clean up its span context
    case :ets.lookup(@monitor_table, ref) do
      [{^ref, ^pid}] ->
        cleanup_process(pid)
        :ets.delete(@monitor_table, ref)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("SpanManager received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp ensure_monitored(pid) do
    # Check if we're already monitoring this process
    case :ets.match(@monitor_table, {:_, pid}) do
      [] ->
        # Not monitoring yet, set up monitor
        ref = Process.monitor(pid)
        :ets.insert(@monitor_table, {ref, pid})

      _ ->
        # Already monitoring
        :ok
    end
  end

  defp cleanup_process(pid) do
    # Remove span context
    :ets.delete(@table_name, pid)

    # Remove monitor if exists
    case :ets.match(@monitor_table, {:"$1", pid}) do
      [[ref]] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(@monitor_table, ref)

      _ ->
        :ok
    end
  end
end
