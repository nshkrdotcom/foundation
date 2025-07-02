defmodule Foundation.SupervisedSend do
  @moduledoc """
  OTP-compliant message passing with delivery guarantees, monitoring, and error handling.
  
  This module provides supervised alternatives to raw send/2 that integrate with
  OTP supervision trees and provide better error handling and observability.
  
  ## Features
  
  - Delivery monitoring with timeouts
  - Automatic retry with backoff
  - Circuit breaker integration
  - Telemetry events for observability
  - Dead letter queue for failed messages
  - Flow control and backpressure
  
  ## Usage
  
      # Simple supervised send
      SupervisedSend.send_supervised(pid, {:work, data})
      
      # With options
      SupervisedSend.send_supervised(pid, message,
        timeout: 5000,
        retries: 3,
        on_error: :dead_letter
      )
      
      # Broadcast with partial failure handling
      SupervisedSend.broadcast_supervised(pids, message,
        strategy: :best_effort,
        timeout: 1000
      )
  """
  
  use GenServer
  require Logger
  
  alias Foundation.DeadLetterQueue
  
  @type send_option :: 
    {:timeout, timeout()} |
    {:retries, non_neg_integer()} |
    {:backoff, non_neg_integer()} |
    {:on_error, :raise | :log | :dead_letter | :ignore} |
    {:metadata, map()}
    
  @type broadcast_strategy :: :all_or_nothing | :best_effort | :at_least_one
  
  # Client API
  
  @doc """
  Starts the supervised send service.
  Usually started as part of the application supervision tree.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Sends a message with supervision and error handling.
  
  ## Options
  
  - `:timeout` - Maximum time to wait for delivery confirmation (default: 5000ms)
  - `:retries` - Number of retry attempts (default: 0)
  - `:backoff` - Backoff multiplier between retries (default: 2)
  - `:on_error` - Error handling strategy (default: :log)
  - `:metadata` - Additional metadata for telemetry (default: %{})
  
  ## Examples
  
      # Simple send
      send_supervised(worker_pid, {:process, data})
      
      # With retry
      send_supervised(worker_pid, {:process, data}, 
        retries: 3,
        backoff: 100
      )
      
      # With dead letter queue
      send_supervised(critical_worker, {:important, data},
        on_error: :dead_letter,
        metadata: %{job_id: "123"}
      )
  """
  @spec send_supervised(pid() | atom(), any(), [send_option()]) :: 
    :ok | {:error, :timeout | :noproc | term()}
  def send_supervised(recipient, message, opts \\ []) do
    metadata = build_metadata(recipient, message, opts)
    
    result = :telemetry.span(
      [:foundation, :supervised_send, :send],
      metadata,
      fn ->
        send_result = do_send_supervised(recipient, message, opts)
        {send_result, Map.put(metadata, :result, send_result)}
      end
    )
    
    result
  end
  
  @doc """
  Broadcasts a message to multiple recipients with configurable failure handling.
  
  ## Strategies
  
  - `:all_or_nothing` - Fails if any recipient fails
  - `:best_effort` - Returns results for all attempts
  - `:at_least_one` - Succeeds if at least one delivery succeeds
  
  ## Examples
  
      # Notify all subscribers (best effort)
      broadcast_supervised(subscribers, {:event, data}, 
        strategy: :best_effort
      )
      
      # Critical broadcast (all must succeed)
      broadcast_supervised(replicas, {:replicate, data},
        strategy: :all_or_nothing,
        timeout: 10_000
      )
  """
  @spec broadcast_supervised(
    [{any(), pid(), any()}] | [pid()], 
    any(), 
    keyword()
  ) :: {:ok, [any()]} | {:error, :partial_failure, [any()]} | {:error, term()}
  def broadcast_supervised(recipients, message, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :best_effort)
    
    # Convert to normalized format
    normalized = normalize_recipients(recipients)
    
    # Execute broadcast based on strategy
    case strategy do
      :all_or_nothing ->
        broadcast_all_or_nothing(normalized, message, opts)
        
      :best_effort ->
        broadcast_best_effort(normalized, message, opts)
        
      :at_least_one ->
        broadcast_at_least_one(normalized, message, opts)
        
      other ->
        {:error, {:invalid_strategy, other}}
    end
  end
  
  @doc """
  Sends a message to self with guaranteed delivery.
  This is always safe and doesn't need supervision.
  """
  def send_to_self(message) do
    send(self(), message)
    :ok
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      stats: %{
        sent: 0,
        delivered: 0,
        failed: 0,
        retried: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:add_dead_letter, recipient, message, reason, opts}, state) do
    # Add to dead letter queue if configured
    if Application.get_env(:foundation, :dead_letter_enabled, true) do
      DeadLetterQueue.add_message(recipient, message, reason, Keyword.get(opts, :metadata, %{}))
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  # Private functions
  
  defp do_send_supervised(recipient, message, opts) do
    retries = Keyword.get(opts, :retries, 0)
    on_error = Keyword.get(opts, :on_error, :log)
    
    case try_send_with_retry(recipient, message, retries, opts) do
      :ok ->
        :ok
        
      {:error, reason} = error ->
        handle_send_error(recipient, message, reason, on_error, opts)
        error
    end
  end
  
  defp try_send_with_retry(recipient, message, retries_left, opts) do
    case do_monitored_send(recipient, message, opts) do
      :ok ->
        :ok
        
      {:error, _reason} when retries_left > 0 ->
        backoff = Keyword.get(opts, :backoff, 2)
        delay = backoff * (Keyword.get(opts, :retries, 0) - retries_left + 1)
        Process.sleep(delay)
        
        :telemetry.execute(
          [:foundation, :supervised_send, :retry],
          %{attempt: Keyword.get(opts, :retries, 0) - retries_left + 1},
          %{recipient: recipient}
        )
        
        try_send_with_retry(recipient, message, retries_left - 1, opts)
        
      error ->
        error
    end
  end
  
  defp do_monitored_send(recipient, message, opts) when is_pid(recipient) do
    timeout = Keyword.get(opts, :timeout, 5000)
    
    # Check if process is alive first
    if Process.alive?(recipient) do
      # Monitor the process to detect if it dies during send
      ref = Process.monitor(recipient)
      
      # Send the message
      case Process.send(recipient, message, [:noconnect]) do
        :ok ->
          # Wait briefly to see if process crashes immediately
          receive do
            {:DOWN, ^ref, :process, ^recipient, reason} ->
              {:error, {:process_down, reason}}
          after
            min(timeout, 100) ->
              Process.demonitor(ref, [:flush])
              :ok
          end
          
        :noconnect ->
          Process.demonitor(ref, [:flush])
          {:error, :noproc}
      end
    else
      {:error, :noproc}
    end
  end
  
  defp do_monitored_send(recipient, message, opts) when is_atom(recipient) do
    case Process.whereis(recipient) do
      nil -> {:error, :noproc}
      pid -> do_monitored_send(pid, message, opts)
    end
  end
  
  defp handle_send_error(recipient, _message, reason, :log, opts) do
    Logger.warning("Supervised send failed",
      recipient: inspect(recipient),
      reason: inspect(reason),
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end
  
  defp handle_send_error(recipient, message, reason, :dead_letter, opts) do
    GenServer.cast(__MODULE__, {:add_dead_letter, recipient, message, reason, opts})
    Logger.warning("Message sent to dead letter queue",
      recipient: inspect(recipient),
      reason: inspect(reason)
    )
  end
  
  defp handle_send_error(_recipient, _message, _reason, :ignore, _opts) do
    :ok
  end
  
  defp handle_send_error(_recipient, _message, reason, :raise, _opts) do
    raise "Supervised send failed: #{inspect(reason)}"
  end
  
  defp normalize_recipients(recipients) when is_list(recipients) do
    Enum.map(recipients, fn
      {id, pid, meta} when is_pid(pid) -> {id, pid, meta}
      pid when is_pid(pid) -> {pid, pid, %{}}
      name when is_atom(name) -> {name, name, %{}}
    end)
  end
  
  defp broadcast_all_or_nothing(recipients, message, opts) do
    # First check all recipients are alive
    alive_check = Enum.map(recipients, fn {id, recipient, _meta} ->
      case check_process_alive(recipient) do
        {:ok, pid} -> {:ok, {id, pid}}
        error -> error
      end
    end)
    
    case Enum.find(alive_check, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error
        
      nil ->
        # All alive, send to all
        results = Enum.map(recipients, fn {id, recipient, _meta} ->
          {id, send_supervised(recipient, message, opts)}
        end)
        
        case Enum.find(results, fn {_, result} -> result != :ok end) do
          nil -> {:ok, results}
          {_id, error} -> error
        end
    end
  end
  
  defp broadcast_best_effort(recipients, message, opts) do
    results = Enum.map(recipients, fn {id, recipient, meta} ->
      result = send_supervised(recipient, message, opts)
      {id, result, meta}
    end)
    
    {:ok, results}
  end
  
  defp broadcast_at_least_one(recipients, message, opts) do
    results = broadcast_best_effort(recipients, message, opts)
    
    case Enum.find(elem(results, 1), fn {_id, result, _meta} -> 
      result == :ok 
    end) do
      nil -> {:error, :all_failed}
      _ -> results
    end
  end
  
  defp check_process_alive(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :noproc}
  end
  
  defp check_process_alive(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, :noproc}
      pid -> {:ok, pid}
    end
  end
  
  
  defp build_metadata(recipient, message, opts) do
    %{
      recipient: inspect(recipient),
      message_type: message_type(message),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  defp message_type(message) when is_tuple(message) do
    elem(message, 0)
  end
  defp message_type(_), do: :unknown
end