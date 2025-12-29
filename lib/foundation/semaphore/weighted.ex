defmodule Foundation.Semaphore.Weighted do
  @moduledoc """
  Weighted semaphore with blocking acquire and negative budget allowance.
  """

  use GenServer

  @type t :: pid()

  @doc """
  Start a weighted semaphore with the given max weight.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_weight = Keyword.fetch!(opts, :max_weight)
    GenServer.start_link(__MODULE__, max_weight, name: opts[:name])
  end

  @doc """
  Acquire weight, blocking when budget is negative.
  """
  @spec acquire(t(), non_neg_integer()) :: :ok
  def acquire(semaphore, weight) when is_integer(weight) and weight >= 0 do
    GenServer.call(semaphore, {:acquire, weight}, :infinity)
  end

  @doc """
  Attempt to acquire weight without blocking.
  """
  @spec try_acquire(t(), non_neg_integer()) :: :ok | {:error, :unavailable}
  def try_acquire(semaphore, weight) when is_integer(weight) and weight >= 0 do
    GenServer.call(semaphore, {:try_acquire, weight})
  end

  @doc """
  Release weight back to the semaphore.
  """
  @spec release(t(), non_neg_integer()) :: :ok
  def release(semaphore, weight) when is_integer(weight) and weight >= 0 do
    GenServer.cast(semaphore, {:release, weight})
  end

  @doc """
  Execute `fun` while holding the requested weight.
  """
  @spec with_acquire(t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_acquire(semaphore, weight, fun) when is_function(fun, 0) do
    acquire(semaphore, weight)

    try do
      fun.()
    after
      release(semaphore, weight)
    end
  end

  @impl true
  def init(max_weight) when is_integer(max_weight) and max_weight > 0 do
    {:ok,
     %{
       max_weight: max_weight,
       current_weight: max_weight,
       waiters: :queue.new()
     }}
  end

  @impl true
  def handle_call({:acquire, weight}, from, %{current_weight: current} = state)
      when current < 0 do
    {:noreply, enqueue_waiter(state, from, weight)}
  end

  def handle_call({:acquire, weight}, _from, state) do
    {:reply, :ok, %{state | current_weight: state.current_weight - weight}}
  end

  @impl true
  def handle_call({:try_acquire, _weight}, _from, %{current_weight: current} = state)
      when current < 0 do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:try_acquire, weight}, _from, state) do
    {:reply, :ok, %{state | current_weight: state.current_weight - weight}}
  end

  @impl true
  def handle_cast({:release, weight}, state) do
    state = %{state | current_weight: state.current_weight + weight}
    {:noreply, maybe_wake_waiters(state)}
  end

  defp enqueue_waiter(state, from, weight) do
    %{state | waiters: :queue.in({from, weight}, state.waiters)}
  end

  defp maybe_wake_waiters(%{current_weight: current} = state) when current < 0, do: state

  defp maybe_wake_waiters(state) do
    case :queue.out(state.waiters) do
      {{:value, {from, weight}}, remaining} ->
        GenServer.reply(from, :ok)

        state
        |> Map.put(:waiters, remaining)
        |> Map.update!(:current_weight, &(&1 - weight))
        |> maybe_wake_waiters()

      {:empty, _} ->
        state
    end
  end
end
