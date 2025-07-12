defmodule Foundation.TestProcess do
  @moduledoc """
  Reusable test process implementations to replace `spawn(fn -> :timer.sleep(:infinity) end)` patterns.

  This module provides proper GenServer-based test processes that can be used in place
  of infinity sleep spawns, ensuring clean supervision and resource management.

  ## Usage

  Replace:
  ```elixir
  pid = spawn(fn -> :timer.sleep(:infinity) end)
  ```

  With:
  ```elixir
  {:ok, pid} = Foundation.TestProcess.start_link()
  ```

  ## Process Types

  - `basic/0` - Simple process that stays alive and responds to basic messages
  - `configurable/1` - Process with configurable behavior patterns
  - `monitored/1` - Process that can be monitored and reports status
  - `interactive/1` - Process that responds to various test messages

  ## Cleanup

  All processes can be terminated with:
  ```elixir
  Foundation.TestProcess.stop(pid)
  ```

  Or they will terminate gracefully when their supervision tree shuts down.
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Start a basic test process that stays alive and responds to `:ping` with `:pong`.

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_link()
      :pong = GenServer.call(pid, :ping)
      Foundation.TestProcess.stop(pid)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Start a basic test process with a specific name.

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_link(name: :my_test_process)
      :pong = GenServer.call(:my_test_process, :ping)
  """
  def start_link_named(name, opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start a configurable test process with specific behavior.

  ## Options

  - `:behavior` - `:normal`, `:slow`, `:error`, `:crash` (default: `:normal`)
  - `:responses` - Map of call => response patterns
  - `:delay` - Milliseconds to delay responses (default: 0)
  - `:crash_after` - Number of calls before crashing (default: never)

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_configurable(behavior: :slow, delay: 100)
      {:ok, pid} = Foundation.TestProcess.start_configurable(
        responses: %{:ping => :pong, :status => :running}
      )
  """
  def start_configurable(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.merge([behavior: :configurable], opts))
  end

  @doc """
  Start an interactive test process that responds to multiple message types.

  This process responds to:
  - `:ping` -> `:pong`
  - `:status` -> `:running`
  - `{:echo, message}` -> `{:echo_response, message}`
  - `{:add_message, msg}` -> Stores message in state
  - `:get_messages` -> Returns stored messages

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_interactive()
      :pong = GenServer.call(pid, :ping)
      :running = GenServer.call(pid, :status)
      GenServer.cast(pid, {:add_message, "test"})
      ["test"] = GenServer.call(pid, :get_messages)
  """
  def start_interactive(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.merge([behavior: :interactive], opts))
  end

  @doc """
  Gracefully stop a test process.

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_link()
      :ok = Foundation.TestProcess.stop(pid)
  """
  def stop(pid, reason \\ :normal, timeout \\ 5000) do
    GenServer.stop(pid, reason, timeout)
  end

  @doc """
  Send a message to a test process (for testing info messages).

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_interactive()
      Foundation.TestProcess.send_info(pid, {:test_message, "hello"})
      messages = GenServer.call(pid, :get_messages)
      assert {:test_message, "hello"} in messages
  """
  def send_info(pid, message) do
    send(pid, message)
  end

  @doc """
  Check if a test process is alive and responsive.

  ## Examples

      {:ok, pid} = Foundation.TestProcess.start_link()
      assert Foundation.TestProcess.alive?(pid) == true
  """
  def alive?(pid) do
    Process.alive?(pid) and
      case GenServer.call(pid, :ping, 1000) do
        :pong -> true
        _ -> false
      end
  rescue
    _ -> false
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    behavior = Keyword.get(opts, :behavior, :normal)

    state = %{
      behavior: behavior,
      messages: [],
      call_count: 0,
      responses: Keyword.get(opts, :responses, %{}),
      delay: Keyword.get(opts, :delay, 0),
      crash_after: Keyword.get(opts, :crash_after, nil),
      started_at: System.monotonic_time(:millisecond)
    }

    Logger.debug("TestProcess started with behavior: #{behavior}")
    {:ok, state}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    handle_call_with_behavior(:ping, :pong, state)
  end

  def handle_call(:status, _from, state) do
    status =
      case state.behavior do
        :error -> :error
        :crash -> :unstable
        _ -> :running
      end

    handle_call_with_behavior(:status, status, state)
  end

  def handle_call(:get_messages, _from, state) do
    handle_call_with_behavior(:get_messages, state.messages, state)
  end

  def handle_call({:echo, message}, _from, state) do
    handle_call_with_behavior({:echo, message}, {:echo_response, message}, state)
  end

  def handle_call(:get_state, _from, state) do
    public_state = %{
      behavior: state.behavior,
      call_count: state.call_count,
      message_count: length(state.messages),
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at
    }

    handle_call_with_behavior(:get_state, public_state, state)
  end

  def handle_call(call, _from, state) do
    # Check for custom responses
    case Map.get(state.responses, call) do
      nil -> handle_call_with_behavior(call, {:unknown_call, call}, state)
      response -> handle_call_with_behavior(call, response, state)
    end
  end

  @impl true
  def handle_cast({:add_message, message}, state) do
    new_messages = [message | state.messages]
    {:noreply, %{state | messages: new_messages}}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(message, %{behavior: :interactive} = state) do
    # Interactive processes store info messages
    new_messages = [message | state.messages]
    {:noreply, %{state | messages: new_messages}}
  end

  def handle_info(_message, state) do
    # Non-interactive processes ignore info messages
    {:noreply, state}
  end

  # Private Functions

  defp handle_call_with_behavior(call, response, state) do
    new_call_count = state.call_count + 1

    # Check if we should crash
    if state.crash_after && new_call_count >= state.crash_after do
      Logger.debug("TestProcess crashing after #{new_call_count} calls")
      exit(:intentional_crash)
    end

    # Apply delay if configured
    if state.delay > 0 do
      Process.sleep(state.delay)
    end

    # Apply behavior-specific handling
    final_response =
      case state.behavior do
        :error when call == :ping ->
          {:error, :simulated_error}

        :slow ->
          # Add extra delay for slow behavior
          Process.sleep(50)
          response

        _ ->
          response
      end

    new_state = %{state | call_count: new_call_count}
    {:reply, final_response, new_state}
  end
end
