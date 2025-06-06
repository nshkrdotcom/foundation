defmodule MockWorker do
  @moduledoc """
  Mock worker for testing pool operations.

  Provides a simple GenServer implementation that can be used to test
  connection pooling functionality without external dependencies.
  """

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    {:ok, %{args: args, call_count: 0}}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, %{state | call_count: state.call_count + 1}}
  end

  def handle_call(:get_call_count, _from, state) do
    {:reply, state.call_count, state}
  end

  def handle_call({:work, data}, _from, state) do
    {:reply, {:ok, data}, %{state | call_count: state.call_count + 1}}
  end

  def handle_call(:simulate_error, _from, state) do
    # Reply with error, then continue to shutdown after reply is sent
    {:reply, :error, state, {:continue, :shutdown}}
  end

  def handle_call(:simulate_immediate_crash, _from, _state) do
    # Crash immediately during the call without sending a reply
    exit(:simulated_error)
  end

  def handle_continue(:shutdown, state) do
    # This runs after the reply has been sent
    {:stop, :simulated_error, state}
  end
end
