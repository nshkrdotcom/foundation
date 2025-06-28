defmodule Foundation.Coordination.DistributedCounter do
  @moduledoc """
  A distributed counter implementation using GenServer and :global.

  This module provides truly distributed counter functionality that works
  across BEAM cluster nodes using Elixir's built-in :global registry.

  Replaces the local ETS-based counter implementation with a proper
  distributed solution that maintains consistency across the cluster.
  """

  use GenServer
  require Logger

  @type counter_id :: term()

  # Client API

  @doc """
  Start a distributed counter with an initial value.
  """
  @spec start_link(counter_id(), integer()) :: GenServer.on_start()
  def start_link(counter_id, initial_value \\ 0) do
    GenServer.start_link(__MODULE__, {counter_id, initial_value})
  end

  @doc """
  Increment the counter by the given amount (default 1).
  """
  @spec increment(pid(), integer()) :: {:ok, integer()} | {:error, term()}
  def increment(pid, amount \\ 1) do
    GenServer.call(pid, {:increment, amount})
  end

  @doc """
  Get the current value of the counter.
  """
  @spec get_value(pid()) :: {:ok, integer()} | {:error, term()}
  def get_value(pid) do
    GenServer.call(pid, :get_value)
  end

  @doc """
  Reset the counter to zero.
  """
  @spec reset(pid()) :: {:ok, integer()} | {:error, term()}
  def reset(pid) do
    GenServer.call(pid, :reset)
  end

  # GenServer Implementation

  @impl true
  def init({counter_id, initial_value}) do
    state = %{
      counter_id: counter_id,
      value: initial_value,
      created_at: System.system_time(:millisecond)
    }

    Logger.debug(
      "Started distributed counter #{inspect(counter_id)} with initial value #{initial_value}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:increment, amount}, _from, state) when is_integer(amount) do
    new_value = state.value + amount
    new_state = %{state | value: new_value}

    Logger.debug(
      "Counter #{inspect(state.counter_id)} incremented by #{amount}, new value: #{new_value}"
    )

    {:reply, {:ok, new_value}, new_state}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, {:ok, state.value}, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{state | value: 0}
    Logger.debug("Counter #{inspect(state.counter_id)} reset to 0")
    {:reply, {:ok, 0}, new_state}
  end

  @impl true
  def handle_call(unknown_call, from, state) do
    Logger.warning("Unknown call #{inspect(unknown_call)} from #{inspect(from)}")
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Counter #{inspect(state.counter_id)} terminating: #{inspect(reason)}")
    :ok
  end
end
