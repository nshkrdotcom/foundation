defmodule JidoFoundation.CoordinationManager do
  @moduledoc """
  Supervised GenServer for managing agent coordination and communication.

  This module replaces the raw message passing in Bridge coordination functions,
  providing proper OTP supervision, process monitoring, and error handling for
  inter-agent communication.

  ## Features

  - Supervised message routing between agents
  - Process monitoring for communication endpoints
  - Circuit breaker patterns for unreliable agents
  - Message buffering for temporary agent unavailability
  - Comprehensive error handling and recovery

  ## Architecture

  Instead of raw `send()` calls without process relationships, this module:
  1. Monitors both sender and receiver processes
  2. Handles dead process scenarios gracefully
  3. Provides delivery confirmation and error reporting
  4. Integrates with OTP supervision trees
  5. Offers message buffering and retry mechanisms

  ## Usage

      # Route a coordination message (supervised)
      JidoFoundation.CoordinationManager.coordinate_agents(
        sender_pid,
        receiver_pid,
        %{action: :collaborate, data: %{}}
      )

      # Distribute a task (supervised)
      JidoFoundation.CoordinationManager.distribute_task(
        coordinator_pid,
        worker_pid,
        %{id: "task_1", type: :processing}
      )
  """

  use GenServer
  require Logger

  defstruct [
    # %{pid() => %{monitor_ref: reference(), last_seen: DateTime.t()}}
    :monitored_processes,
    # %{message_id => %{sender: pid(), receiver: pid(), retry_count: integer()}}
    :pending_messages,
    # %{pid() => [message]}
    :message_buffers,
    :circuit_breakers,
    :stats
  ]

  @type t :: %__MODULE__{}

  # Configuration
  @max_retry_attempts 3
  @retry_delay_ms 1000
  @circuit_breaker_threshold 5
  @buffer_max_size 100

  # Client API

  @doc """
  Starts the coordination manager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Coordinates communication between two agents with proper supervision.

  Replaces raw `send()` calls with supervised message routing.

  ## Parameters

  - `sender_agent` - PID of the sending agent
  - `receiver_agent` - PID of the receiving agent
  - `message` - Coordination message payload

  ## Returns

  - `:ok` - Message sent successfully
  - `{:error, reason}` - Failed to send message
  """
  @spec coordinate_agents(pid(), pid(), map()) :: :ok | {:error, term()}
  def coordinate_agents(sender_agent, receiver_agent, message)
      when is_pid(sender_agent) and is_pid(receiver_agent) do
    GenServer.call(__MODULE__, {:coordinate_agents, sender_agent, receiver_agent, message})
  end

  @doc """
  Distributes a task from coordinator to worker with supervision.

  ## Parameters

  - `coordinator_agent` - PID of the coordinating agent
  - `worker_agent` - PID of the worker agent
  - `task` - Task payload with id and type

  ## Returns

  - `:ok` - Task distributed successfully
  - `{:error, reason}` - Failed to distribute task
  """
  @spec distribute_task(pid(), pid(), map()) :: :ok | {:error, term()}
  def distribute_task(coordinator_agent, worker_agent, task)
      when is_pid(coordinator_agent) and is_pid(worker_agent) do
    GenServer.call(__MODULE__, {:distribute_task, coordinator_agent, worker_agent, task})
  end

  @doc """
  Delegates a task with hierarchical semantics.

  ## Parameters

  - `delegator_agent` - PID of the delegating agent
  - `delegate_agent` - PID of the delegate agent
  - `task` - Task payload

  ## Returns

  - `:ok` - Task delegated successfully
  - `{:error, reason}` - Failed to delegate task
  """
  @spec delegate_task(pid(), pid(), map()) :: :ok | {:error, term()}
  def delegate_task(delegator_agent, delegate_agent, task)
      when is_pid(delegator_agent) and is_pid(delegate_agent) do
    GenServer.call(__MODULE__, {:delegate_task, delegator_agent, delegate_agent, task})
  end

  @doc """
  Creates a coordination context for multiple agents.

  ## Parameters

  - `agents` - List of agent PIDs
  - `context` - Coordination context data

  ## Returns

  - `:ok` - Context created successfully
  - `{:error, reason}` - Failed to create context
  """
  @spec create_coordination_context([pid()], map()) :: :ok | {:error, term()}
  def create_coordination_context(agents, context) when is_list(agents) do
    GenServer.call(__MODULE__, {:create_coordination_context, agents, context})
  end

  @doc """
  Gets coordination statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Forces retry of pending messages.
  """
  @spec retry_pending_messages() :: :ok
  def retry_pending_messages do
    GenServer.cast(__MODULE__, :retry_pending_messages)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Set up process monitoring for itself
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      monitored_processes: %{},
      pending_messages: %{},
      message_buffers: %{},
      circuit_breakers: %{},
      stats: %{
        messages_sent: 0,
        messages_failed: 0,
        processes_monitored: 0,
        buffer_overflows: 0
      }
    }

    Logger.info("JidoFoundation.CoordinationManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:coordinate_agents, sender_agent, receiver_agent, message}, _from, state) do
    case send_coordinated_message(
           sender_agent,
           receiver_agent,
           {:mabeam_coordination, sender_agent, message},
           state
         ) do
      {:ok, new_state} ->
        # Emit telemetry for coordination
        JidoFoundation.Bridge.emit_agent_event(
          sender_agent,
          :coordination,
          %{messages_sent: 1},
          %{
            target_agent: receiver_agent,
            message_type: Map.get(message, :action, :unknown),
            coordination_type: :direct
          }
        )

        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call({:distribute_task, coordinator_agent, worker_agent, task}, _from, state) do
    case send_coordinated_message(
           coordinator_agent,
           worker_agent,
           {:mabeam_task, task.id, task},
           state
         ) do
      {:ok, new_state} ->
        # Emit telemetry for task distribution
        JidoFoundation.Bridge.emit_agent_event(
          coordinator_agent,
          :task_distribution,
          %{tasks_distributed: 1},
          %{
            target_agent: worker_agent,
            task_id: task.id,
            task_type: Map.get(task, :type, :unknown)
          }
        )

        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call({:delegate_task, delegator_agent, delegate_agent, task}, _from, state) do
    case send_coordinated_message(
           delegator_agent,
           delegate_agent,
           {:mabeam_task, task.id, task},
           state
         ) do
      {:ok, new_state} ->
        # Emit telemetry for task delegation
        JidoFoundation.Bridge.emit_agent_event(
          delegator_agent,
          :task_delegation,
          %{tasks_delegated: 1},
          %{
            delegate_agent: delegate_agent,
            task_id: task.id,
            task_type: Map.get(task, :type, :unknown),
            delegation_level: :hierarchical
          }
        )

        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call({:create_coordination_context, agents, context}, _from, state) do
    coordination_id = System.unique_integer()
    enhanced_context = Map.put(context, :coordination_id, coordination_id)

    # Send context to all agents
    results =
      Enum.map(agents, fn agent ->
        send_coordinated_message(
          agent,
          agent,
          {:mabeam_coordination_context, coordination_id, enhanced_context},
          state
        )
      end)

    case Enum.find(results, fn {status, _state} -> status == :error end) do
      nil ->
        # All successful
        final_state = List.last(results) |> elem(1)

        # Emit context creation telemetry
        :telemetry.execute(
          [:jido, :coordination, :context_created],
          %{agent_count: length(agents)},
          %{coordination_id: coordination_id, coordination_type: context[:type]}
        )

        {:reply, :ok, final_state}

      {:error, reason, error_state} ->
        {:reply, {:error, reason}, error_state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        monitored_processes: map_size(state.monitored_processes),
        pending_messages: map_size(state.pending_messages),
        buffered_agents: map_size(state.message_buffers),
        circuit_breaker_count: map_size(state.circuit_breakers)
      })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_cast(:retry_pending_messages, state) do
    new_state = retry_all_pending_messages(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.info("Monitored process #{inspect(pid)} went down: #{inspect(reason)}")

    # Clean up monitoring data
    new_monitored = Map.delete(state.monitored_processes, pid)

    # Handle any pending messages for this process
    new_pending = handle_process_down(pid, state.pending_messages)

    # Clear message buffer for this process
    new_buffers = Map.delete(state.message_buffers, pid)

    new_state = %{
      state
      | monitored_processes: new_monitored,
        pending_messages: new_pending,
        message_buffers: new_buffers
    }

    {:noreply, new_state}
  end

  def handle_info({:retry_message, message_id}, state) do
    case Map.get(state.pending_messages, message_id) do
      nil ->
        # Message no longer pending
        {:noreply, state}

      message_info ->
        new_state = retry_message(message_id, message_info, state)
        {:noreply, new_state}
    end
  end

  def handle_info({:check_circuit_reset, pid}, state) do
    # Try to reset circuit to half-open and drain buffered messages
    new_circuit_breakers =
      Map.update(state.circuit_breakers, pid, %{failures: 0, status: :closed}, fn breaker ->
        %{breaker | status: :half_open}
      end)

    # Attempt to drain buffered messages for this pid
    {new_buffers, new_state} =
      drain_message_buffer(pid, %{state | circuit_breakers: new_circuit_breakers})

    {:noreply, %{new_state | message_buffers: new_buffers}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("CoordinationManager terminating: #{inspect(reason)}")

    # Clean up all process monitors
    Enum.each(state.monitored_processes, fn {_pid, %{monitor_ref: ref}} ->
      Process.demonitor(ref, [:flush])
    end)

    :ok
  end

  # Private helper functions

  defp send_coordinated_message(sender_pid, receiver_pid, message, state) do
    # Monitor processes if not already monitored
    state_with_monitoring = ensure_monitored(sender_pid, state)
    state_with_monitoring = ensure_monitored(receiver_pid, state_with_monitoring)

    # Check circuit breaker
    case check_circuit_breaker(receiver_pid, state_with_monitoring) do
      :ok ->
        attempt_message_delivery(sender_pid, receiver_pid, message, state_with_monitoring)

      {:error, :circuit_open} ->
        # Buffer the message or reject
        Logger.warning("Circuit breaker open for #{inspect(receiver_pid)}, buffering message")
        buffer_message(receiver_pid, message, state_with_monitoring)
    end
  end

  defp attempt_message_delivery(sender_pid, receiver_pid, message, state) do
    if Process.alive?(receiver_pid) do
      # Try GenServer call first for guaranteed delivery
      result =
        try do
          # Attempt supervised delivery with timeout
          GenServer.call(receiver_pid, {:coordination_message, message}, 5000)
          :ok
        catch
          :exit, {:timeout, _} ->
            Logger.debug(
              "GenServer call timed out, falling back to send for #{inspect(receiver_pid)}"
            )

            # Fall back to regular send for compatibility
            send(receiver_pid, message)
            :ok

          :exit, {:noproc, _} ->
            {:error, :receiver_not_found}

          :exit, {:normal, _} ->
            {:error, :receiver_terminated}

          :exit, reason ->
            Logger.debug("GenServer call failed: #{inspect(reason)}, falling back to send")
            # Fall back to regular send for agents that don't implement handle_call
            send(receiver_pid, message)
            :ok
        end

      case result do
        :ok ->
          # Update circuit breaker on success
          new_circuit_breakers =
            update_circuit_breaker(receiver_pid, :success, state.circuit_breakers)

          # Update stats
          new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))

          {:ok, %{state | circuit_breakers: new_circuit_breakers, stats: new_stats}}

        {:error, reason} ->
          handle_delivery_failure(sender_pid, receiver_pid, message, reason, state)
      end
    else
      Logger.warning("Receiver #{inspect(receiver_pid)} is not alive")
      handle_delivery_failure(sender_pid, receiver_pid, message, :process_not_alive, state)
    end
  end

  defp handle_delivery_failure(_sender_pid, receiver_pid, _message, reason, state) do
    # Update circuit breaker
    new_circuit_breakers = update_circuit_breaker(receiver_pid, :failure, state.circuit_breakers)

    # Update stats
    new_stats = Map.update!(state.stats, :messages_failed, &(&1 + 1))

    new_state = %{state | circuit_breakers: new_circuit_breakers, stats: new_stats}

    {:error, reason, new_state}
  end

  defp ensure_monitored(pid, state) do
    case Map.get(state.monitored_processes, pid) do
      nil ->
        # Not monitored, start monitoring
        monitor_ref = Process.monitor(pid)

        monitor_info = %{
          monitor_ref: monitor_ref,
          last_seen: DateTime.utc_now()
        }

        new_monitored = Map.put(state.monitored_processes, pid, monitor_info)
        new_stats = Map.update!(state.stats, :processes_monitored, &(&1 + 1))

        Logger.debug("Started monitoring process #{inspect(pid)}")

        %{state | monitored_processes: new_monitored, stats: new_stats}

      _existing ->
        # Already monitored
        state
    end
  end

  defp check_circuit_breaker(pid, state) do
    case Map.get(state.circuit_breakers, pid) do
      nil -> :ok
      %{status: :open} -> {:error, :circuit_open}
      %{status: :closed} -> :ok
      %{status: :half_open} -> :ok
    end
  end

  defp update_circuit_breaker(pid, event, circuit_breakers) do
    current = Map.get(circuit_breakers, pid, %{failures: 0, status: :closed})

    case event do
      :failure ->
        new_failures = current.failures + 1

        if new_failures >= @circuit_breaker_threshold do
          # Schedule circuit reset check
          Process.send_after(self(), {:check_circuit_reset, pid}, 30_000)

          Map.put(circuit_breakers, pid, %{
            failures: new_failures,
            status: :open,
            opened_at: DateTime.utc_now()
          })
        else
          Map.put(circuit_breakers, pid, %{current | failures: new_failures})
        end

      :success ->
        Map.put(circuit_breakers, pid, %{failures: 0, status: :closed})
    end
  end

  @type coordination_message :: 
    {:mabeam_coordination, pid(), term()} |
    {:mabeam_coordination_context, integer(), map()} |
    {:mabeam_task, term(), term()}
  
  @spec buffer_message(pid(), coordination_message(), map()) :: {:ok, map()}
  defp buffer_message(receiver_pid, message, state) do
    current_buffer = Map.get(state.message_buffers, receiver_pid, [])

    if length(current_buffer) >= @buffer_max_size do
      # Buffer overflow - drop oldest messages
      Logger.warning("Message buffer full for #{inspect(receiver_pid)}, dropping oldest messages")

      # Keep only the most recent messages
      new_buffer = [message | Enum.take(current_buffer, @buffer_max_size - 1)]
      new_buffers = Map.put(state.message_buffers, receiver_pid, new_buffer)
      new_stats = Map.update!(state.stats, :buffer_overflows, &(&1 + 1))

      {:ok, %{state | message_buffers: new_buffers, stats: new_stats}}
    else
      # Add to buffer with sender info for proper delivery
      # Handle both map and tuple messages
      sender = extract_message_sender(message)

      enriched_message = %{
        sender: sender,
        message: message,
        buffered_at: System.monotonic_time(:millisecond)
      }

      new_buffer = [enriched_message | current_buffer]
      new_buffers = Map.put(state.message_buffers, receiver_pid, new_buffer)

      {:ok, %{state | message_buffers: new_buffers}}
    end
  end

  defp drain_message_buffer(pid, state) do
    case Map.get(state.message_buffers, pid, []) do
      [] ->
        {state.message_buffers, state}

      buffered_messages ->
        Logger.info("Draining #{length(buffered_messages)} buffered messages for #{inspect(pid)}")

        # Send messages in original order (reverse since we prepend)
        new_state =
          Enum.reverse(buffered_messages)
          |> Enum.reduce(state, fn %{sender: sender, message: message}, acc_state ->
            case attempt_message_delivery(sender, pid, message, acc_state) do
              {:ok, updated_state} -> updated_state
              {_, _, updated_state} -> updated_state
            end
          end)

        # Clear the buffer for this pid
        new_buffers = Map.delete(new_state.message_buffers, pid)
        {new_buffers, new_state}
    end
  end

  defp handle_process_down(pid, pending_messages) do
    # Remove any pending messages for the dead process
    Enum.reduce(pending_messages, %{}, fn {message_id, message_info}, acc ->
      if message_info.receiver == pid or message_info.sender == pid do
        Logger.debug("Removing pending message #{message_id} due to process death")
        acc
      else
        Map.put(acc, message_id, message_info)
      end
    end)
  end

  defp retry_all_pending_messages(state) do
    Enum.reduce(state.pending_messages, state, fn {message_id, message_info}, acc_state ->
      retry_message(message_id, message_info, acc_state)
    end)
  end

  defp retry_message(message_id, message_info, state) do
    if message_info.retry_count < @max_retry_attempts do
      # Retry the message
      Logger.debug("Retrying message #{message_id}, attempt #{message_info.retry_count + 1}")

      case attempt_message_delivery(
             message_info.sender,
             message_info.receiver,
             message_info.message,
             state
           ) do
        {:ok, new_state} ->
          # Success, remove from pending
          new_pending = Map.delete(new_state.pending_messages, message_id)
          %{new_state | pending_messages: new_pending}

        {:error, _reason, new_state} ->
          # Still failing, update retry count
          updated_message_info = %{message_info | retry_count: message_info.retry_count + 1}
          new_pending = Map.put(new_state.pending_messages, message_id, updated_message_info)

          # Schedule next retry
          Process.send_after(self(), {:retry_message, message_id}, @retry_delay_ms)

          %{new_state | pending_messages: new_pending}
      end
    else
      # Max retries exceeded, give up
      Logger.warning("Message #{message_id} failed after #{@max_retry_attempts} attempts")
      new_pending = Map.delete(state.pending_messages, message_id)
      %{state | pending_messages: new_pending}
    end
  end

  # Helper function to extract sender from various message formats
  # Only tuple messages are passed to this function based on actual usage
  @spec extract_message_sender(
    {:mabeam_coordination, pid(), term()} |
    {:mabeam_coordination_context, integer(), map()} |
    {:mabeam_task, term(), term()}
  ) :: pid()
  defp extract_message_sender(message) do
    case message do
      {:mabeam_coordination, sender, _} -> sender
      {:mabeam_coordination_context, _id, %{sender: sender}} -> sender
      {:mabeam_coordination_context, _id, _context} -> self()
      {:mabeam_task, _, _} -> self()
    end
  end
end
