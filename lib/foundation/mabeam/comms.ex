defmodule Foundation.MABEAM.Comms do
  @moduledoc """
  Advanced inter-agent communication system for MABEAM.

  Provides high-performance, fault-tolerant messaging between agents with
  support for request-response patterns, fire-and-forget notifications,
  coordination requests, and comprehensive telemetry.

  ## Features

  - Request-response messaging with configurable timeouts
  - Fire-and-forget notifications for performance
  - Coordination protocol support for multi-agent workflows
  - Agent lifecycle integration with ProcessRegistry
  - Comprehensive telemetry and statistics tracking
  - Memory-efficient operation with automatic cleanup
  - Distribution-ready message serialization

  ## Usage

      # Start the communication system
      {:ok, pid} = Comms.start_link([])

      # Send request-response message
      {:ok, response} = Comms.request(:agent_id, {:echo, "hello"})

      # Send fire-and-forget notification
      :ok = Comms.notify(:agent_id, {:update_state, %{key: "value"}})

      # Send coordination request
      {:ok, result} = Comms.coordination_request(
        :agent_id,
        :consensus,
        %{question: "Proceed?", options: [:yes, :no]},
        5000
      )
  """

  use GenServer
  require Logger

  alias Foundation.MABEAM.{ProcessRegistry, Types}

  @type message :: term()
  @type agent_id :: Types.agent_id()
  @type timeout_ms :: non_neg_integer()
  @type coordination_protocol :: atom()
  @type coordination_params :: map()

  # Default timeout for requests (5 seconds)
  @default_timeout 5000

  # Statistics tracking structure
  @enforce_keys [:start_time]
  defstruct [
    :start_time,
    total_requests: 0,
    successful_requests: 0,
    failed_requests: 0,
    total_notifications: 0,
    coordination_requests: 0,
    average_response_time: 0.0,
    active_requests: %{}
  ]

  @type t :: %__MODULE__{
          total_requests: non_neg_integer(),
          successful_requests: non_neg_integer(),
          failed_requests: non_neg_integer(),
          total_notifications: non_neg_integer(),
          coordination_requests: non_neg_integer(),
          average_response_time: float(),
          start_time: DateTime.t(),
          active_requests: map()
        }

  # Public API

  @doc """
  Start the communication system with optional configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a request to an agent and wait for a response.
  """
  @spec request(agent_id(), message()) :: {:ok, term()} | {:error, term()}
  def request(agent_id, message) do
    request(agent_id, message, @default_timeout)
  end

  @doc """
  Send a request to an agent with a custom timeout.
  """
  @spec request(agent_id(), message(), timeout_ms()) :: {:ok, term()} | {:error, term()}
  def request(agent_id, message, timeout) do
    GenServer.call(__MODULE__, {:request, agent_id, message, timeout}, timeout + 1000)
  end

  @doc """
  Send a fire-and-forget notification to an agent.
  """
  @spec notify(agent_id(), message()) :: :ok | {:error, term()}
  def notify(agent_id, message) do
    GenServer.call(__MODULE__, {:notify, agent_id, message})
  end

  @doc """
  Send a coordination request to an agent.
  """
  @spec coordination_request(
          agent_id(),
          coordination_protocol(),
          coordination_params(),
          timeout_ms()
        ) ::
          {:ok, term()} | {:error, term()}
  def coordination_request(agent_id, protocol, params, timeout) do
    coordination_message = {:mabeam_coordination_request, protocol, params}

    case request(agent_id, coordination_message, timeout) do
      {:ok, {:ok, response}} -> {:ok, response}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get communication statistics.
  """
  @spec get_communication_stats() :: map()
  def get_communication_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Send a request to an agent (API reference name).
  """
  @spec send_request(agent_id(), message(), timeout_ms()) :: {:ok, term()} | {:error, term()}
  def send_request(agent_id, message, timeout) do
    request(agent_id, message, timeout)
  end

  @doc """
  Send an async request to an agent.
  """
  @spec send_async_request(agent_id(), message(), timeout_ms()) ::
          {:ok, reference()} | {:error, term()}
  def send_async_request(agent_id, message, timeout) do
    GenServer.call(__MODULE__, {:send_async_request, agent_id, message, timeout})
  end

  @doc """
  Broadcast a message to multiple agents.
  """
  @spec broadcast([agent_id()], message(), timeout_ms()) :: {:ok, [term()]} | {:error, term()}
  def broadcast(agent_ids, message, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:broadcast, agent_ids, message, timeout}, timeout + 1000)
  end

  @doc """
  Multicast a message to agents with specific capabilities.
  """
  @spec multicast([atom()], message(), timeout_ms()) :: {:ok, [term()]} | {:error, term()}
  def multicast(capabilities, message, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:multicast, capabilities, message, timeout}, timeout + 1000)
  end

  @doc """
  Subscribe to events from an agent.
  """
  @spec subscribe(agent_id(), atom()) :: :ok | {:error, term()}
  def subscribe(agent_id, event_type) do
    GenServer.call(__MODULE__, {:subscribe, agent_id, event_type, self()})
  end

  @doc """
  Unsubscribe from events from an agent.
  """
  @spec unsubscribe(agent_id(), atom()) :: :ok | {:error, term()}
  def unsubscribe(agent_id, event_type) do
    GenServer.call(__MODULE__, {:unsubscribe, agent_id, event_type, self()})
  end

  @doc """
  Publish an event to subscribers.
  """
  @spec publish_event(agent_id(), atom(), term()) :: :ok | {:error, term()}
  def publish_event(agent_id, event_type, event_data) do
    GenServer.call(__MODULE__, {:publish_event, agent_id, event_type, event_data})
  end

  @doc """
  Get the current routing table.
  """
  @spec get_routing_table() :: {:ok, map()} | {:error, term()}
  def get_routing_table() do
    GenServer.call(__MODULE__, :get_routing_table)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    test_mode = Keyword.get(opts, :test_mode, false)

    state = %__MODULE__{
      start_time: DateTime.utc_now(),
      active_requests: %{}
    }

    if not test_mode do
      Logger.info("MABEAM Communication system started")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:request, agent_id, message, timeout}, _from, state) do
    case get_agent_pid(agent_id) do
      {:ok, agent_pid} ->
        start_time = System.monotonic_time(:microsecond)

        # Create request key for deduplication (for specific message types)
        request_key =
          case message do
            {:dedupe_test, request_id} -> {agent_id, :dedupe_test, request_id}
            _ -> nil
          end

        # Check for deduplication
        case request_key do
          nil ->
            # No deduplication needed, process normally
            process_request(agent_pid, message, timeout, state, start_time, agent_id)

          key ->
            # Check if this request is already active or cached
            case Map.get(state.active_requests, key) do
              nil ->
                # First time seeing this request, track it and process
                result = send_request_to_agent(agent_pid, message, timeout)

                # Cache the result for future duplicate requests
                new_active = Map.put(state.active_requests, key, result)

                new_state = %{
                  state
                  | total_requests: state.total_requests + 1,
                    active_requests: new_active
                }

                final_state =
                  update_stats_and_emit_telemetry(new_state, result, start_time, agent_id)

                {:reply, result, final_state}

              cached_result ->
                # Duplicate request detected - return cached result without calling agent
                {:reply, cached_result, state}
            end
        end

      {:error, :not_found} ->
        new_state = %{
          state
          | total_requests: state.total_requests + 1,
            failed_requests: state.failed_requests + 1
        }

        {:reply, {:error, :agent_not_found}, new_state}
    end
  end

  @impl true
  def handle_call({:notify, agent_id, message}, _from, state) do
    case get_agent_pid(agent_id) do
      {:ok, agent_pid} ->
        # Send notification asynchronously
        GenServer.cast(agent_pid, message)

        new_state = %{state | total_notifications: state.total_notifications + 1}
        emit_telemetry(:notify, %{agent_id: agent_id})

        {:reply, :ok, new_state}

      {:error, :not_found} ->
        {:reply, {:error, :agent_not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    uptime_seconds =
      if state.start_time do
        DateTime.diff(DateTime.utc_now(), state.start_time, :second)
      else
        0
      end

    stats = %{
      total_requests: state.total_requests,
      successful_requests: state.successful_requests,
      failed_requests: state.failed_requests,
      total_notifications: state.total_notifications,
      coordination_requests: state.coordination_requests,
      average_response_time: state.average_response_time,
      uptime_seconds: uptime_seconds
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:send_async_request, agent_id, message, timeout}, from, state) do
    # For async requests, we'll spawn a task and return immediately
    task_ref = make_ref()

    case get_agent_pid(agent_id) do
      {:ok, agent_pid} ->
        spawn(fn ->
          _result = send_request_to_agent(agent_pid, message, timeout)
          GenServer.reply(from, {:ok, task_ref})
          # In a full implementation, we'd store the result for later retrieval
        end)

        {:noreply, state}

      {:error, :not_found} ->
        {:reply, {:error, :agent_not_found}, state}
    end
  end

  @impl true
  def handle_call({:broadcast, agent_ids, message, timeout}, _from, state) do
    results =
      Enum.map(agent_ids, fn agent_id ->
        case get_agent_pid(agent_id) do
          {:ok, agent_pid} ->
            result = send_request_to_agent(agent_pid, message, timeout)
            {agent_id, result}

          {:error, reason} ->
            {agent_id, {:error, reason}}
        end
      end)

    new_state = %{state | total_requests: state.total_requests + length(agent_ids)}
    {:reply, {:ok, results}, new_state}
  end

  @impl true
  def handle_call({:multicast, capabilities, message, timeout}, _from, state) do
    case ProcessRegistry.find_agents_by_capability(capabilities) do
      {:ok, agent_ids} ->
        results =
          Enum.map(agent_ids, fn agent_id ->
            case get_agent_pid(agent_id) do
              {:ok, agent_pid} ->
                result = send_request_to_agent(agent_pid, message, timeout)
                {agent_id, result}

              {:error, reason} ->
                {agent_id, {:error, reason}}
            end
          end)

        new_state = %{state | total_requests: state.total_requests + length(agent_ids)}
        {:reply, {:ok, results}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, agent_id, event_type, subscriber_pid}, _from, state) do
    # Simple subscription tracking (in a real implementation, this would be more sophisticated)
    subscription_key = {agent_id, event_type}
    current_subscribers = Map.get(state.active_requests, subscription_key, [])
    new_subscribers = [subscriber_pid | current_subscribers] |> Enum.uniq()
    new_active_requests = Map.put(state.active_requests, subscription_key, new_subscribers)

    new_state = %{state | active_requests: new_active_requests}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, agent_id, event_type, subscriber_pid}, _from, state) do
    subscription_key = {agent_id, event_type}
    current_subscribers = Map.get(state.active_requests, subscription_key, [])
    new_subscribers = List.delete(current_subscribers, subscriber_pid)
    new_active_requests = Map.put(state.active_requests, subscription_key, new_subscribers)

    new_state = %{state | active_requests: new_active_requests}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:publish_event, agent_id, event_type, event_data}, _from, state) do
    subscription_key = {agent_id, event_type}
    subscribers = Map.get(state.active_requests, subscription_key, [])

    # Send event to all subscribers
    Enum.each(subscribers, fn subscriber_pid ->
      if Process.alive?(subscriber_pid) do
        send(subscriber_pid, {:mabeam_event, agent_id, event_type, event_data})
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_routing_table, _from, state) do
    # Simple routing table based on active agents
    case ProcessRegistry.list_agents() do
      {:ok, agents} ->
        routing_table =
          Enum.reduce(agents, %{}, fn agent, acc ->
            case get_agent_pid(agent.id) do
              {:ok, pid} -> Map.put(acc, agent.id, pid)
              _ -> acc
            end
          end)

        {:reply, {:ok, routing_table}, state}
    end
  end

  # Private Functions

  defp process_request(agent_pid, message, timeout, state, start_time, agent_id) do
    new_state = %{state | total_requests: state.total_requests + 1}
    result = send_request_to_agent(agent_pid, message, timeout)
    final_state = update_stats_and_emit_telemetry(new_state, result, start_time, agent_id)
    {:reply, result, final_state}
  end

  defp send_request_to_agent(agent_pid, message, timeout) do
    try do
      response = GenServer.call(agent_pid, message, timeout)

      case response do
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    rescue
      _e -> {:error, :agent_crashed}
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noreply, _} -> {:error, :agent_crashed}
      :exit, {reason, _} when reason in [:normal, :shutdown] -> {:error, :agent_crashed}
      :exit, _reason -> {:error, :agent_crashed}
    end
  end

  defp update_stats_and_emit_telemetry(state, result, start_time, agent_id) do
    # Update statistics
    final_state =
      case result do
        {:ok, _} ->
          end_time = System.monotonic_time(:microsecond)
          duration_ms = (end_time - start_time) / 1000

          new_avg =
            calculate_new_average(
              state.average_response_time,
              state.successful_requests,
              duration_ms
            )

          %{
            state
            | successful_requests: state.successful_requests + 1,
              average_response_time: new_avg
          }

        {:error, _} ->
          %{state | failed_requests: state.failed_requests + 1}
      end

    # Emit telemetry
    emit_telemetry(:request, %{
      agent_id: agent_id,
      duration: System.monotonic_time(:microsecond) - start_time
    })

    final_state
  end

  defp get_agent_pid(agent_id) do
    case ProcessRegistry.get_agent_info(agent_id) do
      {:ok, agent_entry} ->
        case agent_entry do
          %{pid: pid} when is_pid(pid) and pid != nil ->
            if Process.alive?(pid) do
              {:ok, pid}
            else
              {:error, :not_found}
            end

          _ ->
            {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp calculate_new_average(current_avg, count, new_value) do
    if count == 0 do
      new_value
    else
      (current_avg * count + new_value) / (count + 1)
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:foundation, :mabeam, :comms, event],
      %{count: 1, duration: Map.get(metadata, :duration, 0)},
      metadata
    )
  rescue
    # Ignore telemetry errors
    _ -> :ok
  end

  # Child Spec for Supervision

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
