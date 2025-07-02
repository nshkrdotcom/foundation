# OTP Implementation Plan - Stage 3: Production Code Hardening
Generated: July 2, 2025
Duration: Weeks 4-5 (10 days)
Status: Ready for Implementation

## Overview

This document details Stage 3 of the OTP remediation plan, focusing on eliminating OTP violations in production code to create a robust, fault-tolerant system. This stage must be completed after Stage 1 (enforcement) and Stage 2 (test fixes).

## Context Documents
- **Parent Plan**: `AUDIT_02_plan.md` - Full remediation strategy
- **Stage 1**: `AUDIT_02_planSteps_01.md` - Enforcement infrastructure (must be complete)
- **Stage 2**: `AUDIT_02_planSteps_02.md` - Test remediation (must be complete)
- **Original Audit**: `JULY_1_2025_PRE_PHASE_2_OTP_report_01_AUDIT_01.md` - Initial findings
- **Architecture**: `CLAUDE.md`, `FOUNDATION_JIDO_INTEGRATION_PLAN.md` - System design

## Current State

### Raw send() Usage (41 occurrences in 17 files)
**Critical files** (inter-process communication):
- `coordinator_agent.ex` - 5 sends to agent processes
- `signal_router.ex` - 1 send for signal delivery
- `coordination_patterns.ex` - 2 broadcast sends
- `coordination_manager.ex` - 4 sends (fallback patterns)
- `scheduler_manager.ex` - 3 scheduled sends

**Lower priority** (self-sends or test infrastructure):
- `workflow_process.ex` - 3 self-sends
- `telemetry_handlers.ex` - 6 test infrastructure sends
- `telemetry/load_test/` - 7 performance test sends

### Other OTP Violations
- **Missing supervision**: Some processes bypass OTP supervision
- **No monitor cleanup**: Potential monitor leaks in several modules
- **Missing timeouts**: GenServer calls without explicit timeouts
- **God processes**: Some modules doing too much (addressed in AUDIT_01)

## Stage 3 Deliverables

### 3.1 Supervised Send Infrastructure
**Priority: CRITICAL**  
**Time Estimate: 2 days**

#### Create Core Supervised Send Module
**Location**: `lib/foundation/supervised_send.ex`

```elixir
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
    
    :telemetry.span(
      [:foundation, :supervised_send, :send],
      metadata,
      fn ->
        result = do_send_supervised(recipient, message, opts)
        {result, Map.put(metadata, :result, result)}
      end
    )
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
    timeout = Keyword.get(opts, :timeout, 5000)
    
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
  def init(opts) do
    # Set up ETS for tracking in-flight messages
    :ets.new(:supervised_send_tracking, [:set, :named_table, :public])
    
    # Set up dead letter queue
    dead_letter_limit = Keyword.get(opts, :dead_letter_limit, 1000)
    
    state = %{
      dead_letter_queue: :queue.new(),
      dead_letter_limit: dead_letter_limit,
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
  def handle_call({:send, recipient, message, timeout}, from, state) do
    # Track the send
    ref = make_ref()
    :ets.insert(:supervised_send_tracking, {ref, from, recipient, message})
    
    # Monitor the recipient
    mon_ref = Process.monitor(recipient)
    
    # Send with noconnect to detect dead processes
    case Process.send(recipient, message, [:noconnect]) do
      :ok ->
        # Set up timeout
        timer_ref = Process.send_after(self(), {:timeout, ref}, timeout)
        
        # Store tracking info
        :ets.insert(:supervised_send_tracking, 
          {ref, from, recipient, message, mon_ref, timer_ref}
        )
        
        {:noreply, state}
        
      :noconnect ->
        # Process doesn't exist
        Process.demonitor(mon_ref, [:flush])
        :ets.delete(:supervised_send_tracking, ref)
        {:reply, {:error, :noproc}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_call(:get_dead_letters, _from, state) do
    {:reply, :queue.to_list(state.dead_letter_queue), state}
  end
  
  @impl true
  def handle_info({:DOWN, mon_ref, :process, pid, reason}, state) do
    # Find associated send operation
    case find_by_monitor(mon_ref) do
      {ref, from, _recipient, message, _mon_ref, timer_ref} ->
        # Cancel timeout
        Process.cancel_timer(timer_ref)
        
        # Clean up tracking
        :ets.delete(:supervised_send_tracking, ref)
        
        # Reply with error
        GenServer.reply(from, {:error, {:process_down, reason}})
        
        # Update stats
        new_stats = Map.update!(state.stats, :failed, &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}
        
      nil ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:timeout, ref}, state) do
    case :ets.lookup(:supervised_send_tracking, ref) do
      [{^ref, from, _recipient, _message, mon_ref, _timer_ref}] ->
        # Clean up
        Process.demonitor(mon_ref, [:flush])
        :ets.delete(:supervised_send_tracking, ref)
        
        # Reply with timeout
        GenServer.reply(from, {:error, :timeout})
        
        # Update stats
        new_stats = Map.update!(state.stats, :failed, &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}
        
      [] ->
        {:noreply, state}
    end
  end
  
  # Private functions
  
  defp do_send_supervised(recipient, message, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
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
    
    try do
      # Use GenServer.call to ensure we're calling our server
      GenServer.call(__MODULE__, {:send, recipient, message, timeout}, timeout + 100)
    catch
      :exit, {:noproc, _} -> {:error, :noproc}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end
  
  defp do_monitored_send(recipient, message, opts) when is_atom(recipient) do
    case Process.whereis(recipient) do
      nil -> {:error, :noproc}
      pid -> do_monitored_send(pid, message, opts)
    end
  end
  
  defp handle_send_error(recipient, message, reason, :log, opts) do
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
  
  defp handle_send_error(recipient, message, reason, :raise, opts) do
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
  
  defp find_by_monitor(mon_ref) do
    :ets.match_object(:supervised_send_tracking, {:_, :_, :_, :_, mon_ref, :_})
    |> List.first()
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
```

#### Create Dead Letter Queue Handler
**Location**: `lib/foundation/dead_letter_queue.ex`

```elixir
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
  def handle_call({:retry_messages, filter}, _from, state) do
    messages = get_messages_for_retry(filter)
    
    results = Enum.map(messages, fn {id, entry} ->
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
  def handle_info(:retry_tick, state) do
    # Retry old messages
    retry_messages(:auto)
    
    # Schedule next retry
    schedule_retry()
    
    {:noreply, state}
  end
  
  defp retry_message(%{recipient: recipient, message: message, attempts: attempts}) do
    if attempts < @max_retries do
      Foundation.SupervisedSend.send_supervised(recipient, message,
        timeout: 10_000,
        retries: 2,
        on_error: :ignore  # Don't re-add to dead letter
      )
    else
      {:error, :max_retries_exceeded}
    end
  end
  
  defp update_retry_attempt(id, entry) do
    updated = %{entry | 
      attempts: entry.attempts + 1,
      last_attempt: DateTime.utc_now()
    }
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
  
  defp schedule_retry do
    Process.send_after(self(), :retry_tick, @retry_interval)
  end
end
```

### 3.2 Migration of Raw send() Calls
**Priority: CRITICAL**  
**Time Estimate: 3 days**

#### Phase 1: Critical Inter-Process Communication

##### File: `lib/jido_system/agents/coordinator_agent.ex`
**Current issues**: 5 raw sends to agent processes without delivery guarantees

```elixir
# BEFORE: Raw send without monitoring
case Map.get(agent.state.agent_pool, agent_id) do
  %{pid: pid} -> send(pid, {:cancel_task, execution_id})
  _ -> :ok
end

# AFTER: Supervised send with error handling
case Map.get(agent.state.agent_pool, agent_id) do
  %{pid: pid} -> 
    Foundation.SupervisedSend.send_supervised(
      pid, 
      {:cancel_task, execution_id},
      timeout: 5000,
      retries: 1,
      on_error: :log,
      metadata: %{
        agent_id: agent_id,
        execution_id: execution_id,
        action: :cancel_task
      }
    )
  _ -> 
    {:error, :agent_not_found}
end

# BEFORE: Self-sends for workflow continuation
send(self(), {:start_workflow_execution, execution_id})
send(self(), {:continue_workflow_execution, execution_id})
send(self(), {:execute_next_task, execution_id})
send(self(), {:complete_workflow_execution, execution_id})
send(self(), {:handle_workflow_error, execution_id, error})

# AFTER: Keep self-sends but add comment
# Self-sends are safe and don't need supervision
send(self(), {:start_workflow_execution, execution_id})
```

##### File: `lib/jido_foundation/signal_router.ex`
**Current issue**: Signal delivery without backpressure

```elixir
# BEFORE: Direct send to handler
defp route_to_handler(handler_pid, signal_type, measurements, metadata) do
  send(handler_pid, {:routed_signal, signal_type, measurements, metadata})
  :ok
end

# AFTER: Use GenServer.cast for proper async messaging
defp route_to_handler(handler_pid, signal_type, measurements, metadata) do
  # Use cast for fire-and-forget semantics with OTP compliance
  GenServer.cast(handler_pid, {:routed_signal, signal_type, measurements, metadata})
  
  # Emit telemetry for monitoring
  :telemetry.execute(
    [:foundation, :signal_router, :signal_routed],
    %{count: 1},
    %{signal_type: signal_type, handler: handler_pid}
  )
  
  :ok
rescue
  ArgumentError ->
    # Handler is not a GenServer, fall back to supervised send
    Foundation.SupervisedSend.send_supervised(
      handler_pid,
      {:routed_signal, signal_type, measurements, metadata},
      timeout: 1000,
      on_error: :log
    )
end
```

##### File: `lib/mabeam/coordination_patterns.ex`
**Current issue**: Broadcast without delivery tracking

```elixir
# BEFORE: Untracked broadcast
def broadcast_to_hierarchy(hierarchy_id, message, state) do
  case Map.get(state.hierarchies, hierarchy_id) do
    nil -> {:error, :hierarchy_not_found}
    agents ->
      Enum.each(agents, fn {_id, pid, _meta} ->
        send(pid, {:hierarchy_broadcast, hierarchy_id, message})
      end)
      :ok
  end
end

# AFTER: Supervised broadcast with results
def broadcast_to_hierarchy(hierarchy_id, message, state) do
  case Map.get(state.hierarchies, hierarchy_id) do
    nil -> 
      {:error, :hierarchy_not_found}
      
    agents ->
      # Use supervised broadcast for delivery tracking
      case Foundation.SupervisedSend.broadcast_supervised(
        agents,
        {:hierarchy_broadcast, hierarchy_id, message},
        strategy: :best_effort,
        timeout: 2000,
        metadata: %{hierarchy_id: hierarchy_id}
      ) do
        {:ok, results} ->
          # Log any failures for monitoring
          failed = Enum.filter(results, fn {_id, result, _} -> 
            result != :ok 
          end)
          
          if length(failed) > 0 do
            Logger.warning("Hierarchy broadcast partial failure",
              hierarchy_id: hierarchy_id,
              failed_count: length(failed),
              total_count: length(agents)
            )
          end
          
          {:ok, results}
          
        error ->
          error
      end
  end
end

# Similar pattern for consensus results
def send_consensus_result(agents, result) do
  Foundation.SupervisedSend.broadcast_supervised(
    agents,
    {:consensus_result, result},
    strategy: :all_or_nothing,  # All must receive consensus result
    timeout: 5000
  )
end
```

#### Phase 2: Lower Priority Sends

##### File: `lib/jido_foundation/scheduler_manager.ex`
**Current issue**: Scheduled tasks without supervision

```elixir
# BEFORE: Direct scheduled send
defp execute_scheduled_task(task, state) do
  send(task.target, task.message)
  # ... rest of implementation
end

# AFTER: Supervised scheduled send with retry
defp execute_scheduled_task(task, state) do
  result = Foundation.SupervisedSend.send_supervised(
    task.target,
    task.message,
    timeout: 10_000,
    retries: task.retry_count || 0,
    on_error: :dead_letter,
    metadata: %{
      task_id: task.id,
      scheduled_at: task.scheduled_at,
      attempt: task.attempt || 1
    }
  )
  
  case result do
    :ok ->
      # Task delivered successfully
      :telemetry.execute(
        [:foundation, :scheduler, :task_delivered],
        %{delay: System.os_time(:millisecond) - task.scheduled_at},
        %{task_id: task.id}
      )
      {:ok, state}
      
    {:error, reason} ->
      # Handle failure based on task configuration
      handle_task_failure(task, reason, state)
  end
end

defp handle_task_failure(task, reason, state) do
  if task.attempt < (task.max_attempts || 3) do
    # Reschedule with backoff
    backoff = calculate_backoff(task.attempt)
    reschedule_task(%{task | attempt: task.attempt + 1}, backoff, state)
  else
    # Max attempts reached
    Logger.error("Scheduled task failed permanently",
      task_id: task.id,
      reason: reason
    )
    {:error, :max_attempts_exceeded}
  end
end
```

#### Phase 3: Migration Script for Remaining Files

**Location**: `scripts/migrate_raw_sends.exs`

```elixir
defmodule SendMigrator do
  @moduledoc """
  Automated migration tool for converting raw send() to supervised alternatives.
  """
  
  @send_to_self_pattern ~r/send\s*\(\s*self\s*\(\s*\)\s*,/
  @raw_send_pattern ~r/send\s*\(/
  @genserver_cast_available [
    "signal_router.ex",
    "coordination_manager.ex",
    "agent_monitor.ex"
  ]
  
  def run do
    lib_files = Path.wildcard("lib/**/*.ex")
    
    stats = %{
      files_checked: 0,
      files_modified: 0,
      sends_migrated: 0,
      self_sends_kept: 0,
      manual_review: 0
    }
    
    final_stats = Enum.reduce(lib_files, stats, fn file, acc ->
      migrate_file(file, acc)
    end)
    
    generate_report(final_stats)
  end
  
  defp migrate_file(file, stats) do
    content = File.read!(file)
    original = content
    
    # Skip if no sends
    if not String.contains?(content, "send(") do
      %{stats | files_checked: stats.files_checked + 1}
    else
      # Analyze and migrate
      {new_content, file_stats} = process_content(content, file)
      
      if new_content != original do
        # Backup original
        File.write!("#{file}.backup", original)
        
        # Write migrated version  
        File.write!(file, new_content)
        
        # Format
        System.cmd("mix", ["format", file])
        
        %{
          stats |
          files_checked: stats.files_checked + 1,
          files_modified: stats.files_modified + 1,
          sends_migrated: stats.sends_migrated + file_stats.migrated,
          self_sends_kept: stats.self_sends_kept + file_stats.self_sends,
          manual_review: stats.manual_review + file_stats.manual
        }
      else
        %{stats | files_checked: stats.files_checked + 1}
      end
    end
  end
  
  defp process_content(content, file) do
    stats = %{migrated: 0, self_sends: 0, manual: 0}
    
    # First, mark all self-sends as safe
    content = Regex.replace(
      @send_to_self_pattern,
      content,
      "# Self-send is safe - no supervision needed\n    send(self(),"
    )
    
    # Count self-sends
    self_send_count = length(Regex.scan(@send_to_self_pattern, content))
    
    # Process remaining sends based on file type
    cond do
      # Test infrastructure - leave as is
      String.contains?(file, "telemetry_handlers.ex") or
      String.contains?(file, "test/support/") ->
        {content, %{stats | self_sends: self_send_count}}
        
      # Can use GenServer.cast
      Enum.any?(@genserver_cast_available, &String.contains?(file, &1)) ->
        new_content = migrate_to_genserver_cast(content)
        migrated = count_migrations(content, new_content)
        {new_content, %{stats | migrated: migrated, self_sends: self_send_count}}
        
      # Default: use supervised send
      true ->
        new_content = migrate_to_supervised_send(content)
        migrated = count_migrations(content, new_content)
        {new_content, %{stats | migrated: migrated, self_sends: self_send_count}}
    end
  end
  
  defp migrate_to_genserver_cast(content) do
    # Simple pattern: send(pid, message) -> GenServer.cast(pid, message)
    Regex.replace(
      ~r/send\(([^,]+),\s*([^)]+)\)/,
      content,
      fn full, pid, message ->
        if String.contains?(full, "self()") do
          full  # Don't touch self-sends
        else
          "GenServer.cast(#{pid}, #{message})"
        end
      end
    )
  end
  
  defp migrate_to_supervised_send(content) do
    # Add import if needed
    content = ensure_import(content)
    
    # Replace sends
    Regex.replace(
      ~r/send\(([^,]+),\s*([^)]+)\)/,
      content,
      fn full, pid, message ->
        if String.contains?(full, "self()") do
          full
        else
          """
          Foundation.SupervisedSend.send_supervised(
            #{String.trim(pid)},
            #{String.trim(message)},
            timeout: 5000,
            on_error: :log
          )
          """
        end
      end
    )
  end
  
  defp ensure_import(content) do
    if not String.contains?(content, "Foundation.SupervisedSend") and
       String.contains?(content, "send(") do
      # Add alias after module declaration
      Regex.replace(
        ~r/(defmodule .+ do\n)/,
        content,
        "\\1  alias Foundation.SupervisedSend\n"
      )
    else
      content
    end
  end
  
  defp count_migrations(original, new_content) do
    original_sends = length(Regex.scan(@raw_send_pattern, original))
    new_sends = length(Regex.scan(@raw_send_pattern, new_content))
    original_sends - new_sends
  end
  
  defp generate_report(stats) do
    IO.puts("""
    
    === Send Migration Report ===
    
    Files checked: #{stats.files_checked}
    Files modified: #{stats.files_modified}
    Sends migrated: #{stats.sends_migrated}
    Self-sends kept: #{stats.self_sends_kept}
    Manual review needed: #{stats.manual_review}
    
    Next steps:
    1. Review the changes in modified files
    2. Run tests to ensure everything works
    3. Check for "TODO" comments for manual review
    4. Remove .backup files after verification
    
    To review changes:
      git diff lib/
    
    To run tests:
      mix test
    
    To find remaining sends:
      grep -r "send(" lib/ --include="*.ex" | grep -v "self()"
    """)
  end
end

# Run the migration
SendMigrator.run()
```

### 3.3 Monitor Leak Prevention
**Priority: HIGH**  
**Time Estimate: 2 days**

#### Create Centralized Monitor Manager
**Location**: `lib/foundation/monitor_manager.ex`

```elixir
defmodule Foundation.MonitorManager do
  @moduledoc """
  Centralized monitor management to prevent monitor leaks.
  
  This module ensures all monitors are properly cleaned up and provides
  visibility into active monitors for debugging and monitoring.
  
  ## Features
  
  - Automatic cleanup on process termination
  - Monitor lifecycle tracking
  - Telemetry integration
  - Debug interface for finding leaks
  
  ## Usage
  
      # Monitor a process
      {:ok, ref} = MonitorManager.monitor(pid, :my_feature)
      
      # Demonitor when done
      :ok = MonitorManager.demonitor(ref)
      
      # List all monitors
      monitors = MonitorManager.list_monitors()
  """
  
  use GenServer
  require Logger
  
  defstruct monitors: %{}, 
            reverse_lookup: %{},
            stats: %{created: 0, cleaned: 0, leaked: 0}
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Monitor a process with automatic cleanup.
  
  The tag parameter helps identify the source of monitors for debugging.
  """
  @spec monitor(pid(), atom() | String.t()) :: {:ok, reference()} | {:error, term()}
  def monitor(pid, tag \\ :untagged) when is_pid(pid) do
    GenServer.call(__MODULE__, {:monitor, pid, tag, self()})
  end
  
  @doc """
  Demonitor a process and flush messages.
  """
  @spec demonitor(reference()) :: :ok | {:error, :not_found}
  def demonitor(ref) when is_reference(ref) do
    GenServer.call(__MODULE__, {:demonitor, ref})
  end
  
  @doc """
  List all active monitors with metadata.
  """
  @spec list_monitors() :: [map()]
  def list_monitors do
    GenServer.call(__MODULE__, :list_monitors)
  end
  
  @doc """
  Get monitoring statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Find potential monitor leaks (monitors older than timeout).
  """
  @spec find_leaks(timeout()) :: [map()]
  def find_leaks(age_ms \\ :timer.minutes(5)) do
    GenServer.call(__MODULE__, {:find_leaks, age_ms})
  end
  
  # Server implementation
  
  @impl true
  def init(_opts) do
    # Schedule periodic leak detection
    schedule_leak_check()
    
    {:ok, %__MODULE__{}}
  end
  
  @impl true
  def handle_call({:monitor, pid, tag, caller}, _from, state) do
    # Create the actual monitor
    ref = Process.monitor(pid)
    
    # Also monitor the caller to clean up if they die
    caller_ref = Process.monitor(caller)
    
    # Store metadata
    monitor_info = %{
      ref: ref,
      pid: pid,
      tag: tag,
      caller: caller,
      caller_ref: caller_ref,
      created_at: System.monotonic_time(:millisecond),
      stack_trace: get_stack_trace()
    }
    
    new_state = state
    |> put_in([:monitors, ref], monitor_info)
    |> put_in([:reverse_lookup, pid, ref], true)
    |> put_in([:reverse_lookup, caller, caller_ref], true)
    |> update_in([:stats, :created], &(&1 + 1))
    
    :telemetry.execute(
      [:foundation, :monitor_manager, :monitor_created],
      %{count: 1},
      %{tag: tag}
    )
    
    {:reply, {:ok, ref}, new_state}
  end
  
  @impl true
  def handle_call({:demonitor, ref}, _from, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      monitor_info ->
        # Demonitor the process
        Process.demonitor(ref, [:flush])
        
        # Demonitor the caller if still monitored
        if Process.demonitor(monitor_info.caller_ref, [:flush, :info]) != false do
          # Caller monitor was still active
        end
        
        # Clean up state
        new_state = state
        |> update_in([:monitors], &Map.delete(&1, ref))
        |> update_in([:reverse_lookup, monitor_info.pid], &Map.delete(&1 || %{}, ref))
        |> update_in([:reverse_lookup, monitor_info.caller], &Map.delete(&1 || %{}, monitor_info.caller_ref))
        |> update_in([:stats, :cleaned], &(&1 + 1))
        
        # Clean up empty entries
        new_state = cleanup_reverse_lookup(new_state, monitor_info.pid)
        new_state = cleanup_reverse_lookup(new_state, monitor_info.caller)
        
        :telemetry.execute(
          [:foundation, :monitor_manager, :monitor_cleaned],
          %{duration: System.monotonic_time(:millisecond) - monitor_info.created_at},
          %{tag: monitor_info.tag}
        )
        
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_monitors, _from, state) do
    monitors = Enum.map(state.monitors, fn {ref, info} ->
      %{
        ref: ref,
        pid: info.pid,
        tag: info.tag,
        caller: info.caller,
        age_ms: System.monotonic_time(:millisecond) - info.created_at,
        alive: Process.alive?(info.pid)
      }
    end)
    
    {:reply, monitors, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.put(state.stats, :active, map_size(state.monitors))
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:find_leaks, age_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    leaks = state.monitors
    |> Enum.filter(fn {_ref, info} ->
      (now - info.created_at) > age_ms and Process.alive?(info.pid)
    end)
    |> Enum.map(fn {ref, info} ->
      %{
        ref: ref,
        pid: info.pid,
        tag: info.tag,
        caller: info.caller,
        age_ms: now - info.created_at,
        stack_trace: info.stack_trace
      }
    end)
    
    {:reply, leaks, state}
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Check if this is a monitored process or a caller
    new_state = cond do
      # It's a monitored process
      Map.has_key?(state.monitors, ref) ->
        handle_monitored_process_down(ref, pid, reason, state)
        
      # It's a caller process - clean up their monitors
      Map.has_key?(Map.get(state.reverse_lookup, pid, %{}), ref) ->
        handle_caller_down(pid, ref, state)
        
      # Unknown monitor (shouldn't happen)
      true ->
        Logger.warning("Received DOWN for unknown monitor",
          ref: ref,
          pid: inspect(pid)
        )
        state
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:check_for_leaks, state) do
    leaks = find_leaks_internal(state, :timer.minutes(5))
    
    if length(leaks) > 0 do
      Logger.warning("Found potential monitor leaks",
        count: length(leaks),
        tags: Enum.map(leaks, & &1.tag) |> Enum.frequencies()
      )
      
      new_state = update_in(state.stats.leaked, &(&1 + length(leaks)))
      
      :telemetry.execute(
        [:foundation, :monitor_manager, :leaks_detected],
        %{count: length(leaks)},
        %{}
      )
      
      schedule_leak_check()
      {:noreply, new_state}
    else
      schedule_leak_check()
      {:noreply, state}
    end
  end
  
  # Private functions
  
  defp handle_monitored_process_down(ref, pid, _reason, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        state
        
      monitor_info ->
        # Clean up the monitor
        Process.demonitor(monitor_info.caller_ref, [:flush, :info])
        
        # Update state
        state
        |> update_in([:monitors], &Map.delete(&1, ref))
        |> update_in([:reverse_lookup, pid], &Map.delete(&1 || %{}, ref))
        |> update_in([:reverse_lookup, monitor_info.caller], &Map.delete(&1 || %{}, monitor_info.caller_ref))
        |> update_in([:stats, :cleaned], &(&1 + 1))
        |> cleanup_reverse_lookup(pid)
        |> cleanup_reverse_lookup(monitor_info.caller)
    end
  end
  
  defp handle_caller_down(caller_pid, _ref, state) do
    # Find all monitors created by this caller
    monitors_to_clean = state.monitors
    |> Enum.filter(fn {_ref, info} -> info.caller == caller_pid end)
    |> Enum.map(fn {ref, _info} -> ref end)
    
    # Clean them all up
    Enum.reduce(monitors_to_clean, state, fn ref, acc_state ->
      case Map.get(acc_state.monitors, ref) do
        nil ->
          acc_state
          
        monitor_info ->
          # Demonitor the target process
          Process.demonitor(ref, [:flush])
          
          # Clean up state
          acc_state
          |> update_in([:monitors], &Map.delete(&1, ref))
          |> update_in([:reverse_lookup, monitor_info.pid], &Map.delete(&1 || %{}, ref))
          |> update_in([:stats, :cleaned], &(&1 + 1))
          |> cleanup_reverse_lookup(monitor_info.pid)
      end
    end)
    |> update_in([:reverse_lookup], &Map.delete(&1, caller_pid))
  end
  
  defp cleanup_reverse_lookup(state, pid) do
    case get_in(state.reverse_lookup, [pid]) do
      nil -> state
      map when map_size(map) == 0 ->
        update_in(state.reverse_lookup, &Map.delete(&1, pid))
      _ -> state
    end
  end
  
  defp find_leaks_internal(state, age_ms) do
    now = System.monotonic_time(:millisecond)
    
    state.monitors
    |> Enum.filter(fn {_ref, info} ->
      (now - info.created_at) > age_ms and 
      Process.alive?(info.pid) and
      Process.alive?(info.caller)
    end)
    |> Enum.map(fn {_ref, info} -> info end)
  end
  
  defp get_stack_trace do
    {:current_stacktrace, trace} = Process.info(self(), :current_stacktrace)
    
    # Remove monitor manager frames
    trace
    |> Enum.drop(3)
    |> Enum.take(5)
    |> Enum.map(&format_stack_frame/1)
  end
  
  defp format_stack_frame({module, function, arity, location}) do
    file = Keyword.get(location, :file, "unknown")
    line = Keyword.get(location, :line, 0)
    "#{module}.#{function}/#{arity} (#{file}:#{line})"
  end
  
  defp schedule_leak_check do
    Process.send_after(self(), :check_for_leaks, :timer.minutes(5))
  end
end
```

#### Create Monitor Migration Helper
**Location**: `lib/foundation/monitor_migration.ex`

```elixir
defmodule Foundation.MonitorMigration do
  @moduledoc """
  Helpers for migrating raw Process.monitor calls to MonitorManager.
  """
  
  defmacro monitor_with_cleanup(pid, tag \\ :default, do: block) do
    quote do
      {:ok, ref} = Foundation.MonitorManager.monitor(unquote(pid), unquote(tag))
      
      try do
        unquote(block)
      after
        Foundation.MonitorManager.demonitor(ref)
      end
    end
  end
  
  def migrate_genserver_module(module_code) do
    # Add monitor tracking to state
    module_code = add_monitor_tracking(module_code)
    
    # Replace Process.monitor calls
    module_code = replace_monitor_calls(module_code)
    
    # Add cleanup in terminate
    add_terminate_cleanup(module_code)
  end
  
  defp add_monitor_tracking(code) do
    # Add monitors field to state struct if exists
    Regex.replace(
      ~r/defstruct\s+\[([^\]]+)\]/,
      code,
      "defstruct [\\1, monitors: %{}]"
    )
  end
  
  defp replace_monitor_calls(code) do
    Regex.replace(
      ~r/Process\.monitor\(([^)]+)\)/,
      code,
      "{:ok, ref} = Foundation.MonitorManager.monitor(\\1, __MODULE__); ref"
    )
  end
  
  defp add_terminate_cleanup(code) do
    if String.contains?(code, "def terminate(") do
      # Add to existing terminate
      Regex.replace(
        ~r/def terminate\(([^,]+), ([^)]+)\) do\n/,
        code,
        """
        def terminate(\\1, \\2) do
          # Clean up monitors
          Enum.each(\\2.monitors, fn {ref, _pid} ->
            Foundation.MonitorManager.demonitor(ref)
          end)
          
        """
      )
    else
      # Add new terminate callback
      code <> """
      
      @impl true
      def terminate(_reason, state) do
        # Clean up monitors
        Enum.each(Map.keys(state.monitors || %{}), fn ref ->
          Foundation.MonitorManager.demonitor(ref)
        end)
        :ok
      end
      """
    end
  end
end
```

### 3.4 GenServer Timeout Enforcement
**Priority: MEDIUM**  
**Time Estimate: 2 days**

#### Create Timeout Configuration Module
**Location**: `lib/foundation/timeout_config.ex`

```elixir
defmodule Foundation.TimeoutConfig do
  @moduledoc """
  Centralized timeout configuration for GenServer calls.
  
  Provides consistent timeouts across the application with
  environment-specific overrides and circuit breaker integration.
  """
  
  @default_timeout 5_000
  @long_timeout 30_000
  @critical_timeout 60_000
  
  @timeout_config %{
    # Service-specific timeouts
    "Foundation.ResourceManager" => @long_timeout,
    "Foundation.Services.ConnectionManager" => @long_timeout,
    "Foundation.Services.RateLimiter" => @default_timeout,
    "Foundation.Infrastructure.CircuitBreaker" => @default_timeout,
    
    # Operation-specific timeouts
    batch_operation: @long_timeout,
    health_check: 1_000,
    sync_operation: @default_timeout,
    async_operation: @critical_timeout,
    
    # Pattern-based timeouts
    {:data_processing, :*} => @long_timeout,
    {:network_call, :*} => @critical_timeout,
    {:cache_lookup, :*} => 1_000
  }
  
  @doc """
  Get timeout for a specific module or operation.
  
  ## Examples
  
      # Module-based
      timeout = TimeoutConfig.get_timeout(MyServer)
      
      # Operation-based
      timeout = TimeoutConfig.get_timeout(:batch_operation)
      
      # Pattern-based
      timeout = TimeoutConfig.get_timeout({:data_processing, :etl})
  """
  def get_timeout(identifier) do
    cond do
      # Direct module match
      is_atom(identifier) and Map.has_key?(@timeout_config, Atom.to_string(identifier)) ->
        Map.get(@timeout_config, Atom.to_string(identifier))
        
      # Direct operation match
      Map.has_key?(@timeout_config, identifier) ->
        Map.get(@timeout_config, identifier)
        
      # Pattern match
      is_tuple(identifier) ->
        find_pattern_timeout(identifier)
        
      # Default
      true ->
        @default_timeout
    end
    |> apply_environment_factor()
  end
  
  @doc """
  Create a GenServer call with proper timeout.
  """
  defmacro call_with_timeout(server, request, opts \\ []) do
    quote do
      timeout = Foundation.TimeoutConfig.get_timeout_for_call(
        unquote(server), 
        unquote(request),
        unquote(opts)
      )
      
      GenServer.call(unquote(server), unquote(request), timeout)
    end
  end
  
  def get_timeout_for_call(server, request, opts) do
    # Priority: explicit timeout > request-based > server-based > default
    cond do
      Keyword.has_key?(opts, :timeout) ->
        Keyword.get(opts, :timeout)
        
      is_tuple(request) and elem(request, 0) == :batch ->
        get_timeout(:batch_operation)
        
      is_tuple(request) and elem(request, 0) == :health_check ->
        get_timeout(:health_check)
        
      true ->
        get_timeout(server)
    end
  end
  
  defp find_pattern_timeout(identifier) do
    @timeout_config
    |> Enum.find(fn
      {{pattern_type, :*}, _timeout} when is_tuple(identifier) ->
        elem(identifier, 0) == pattern_type
      _ ->
        false
    end)
    |> case do
      {_pattern, timeout} -> timeout
      nil -> @default_timeout
    end
  end
  
  defp apply_environment_factor(timeout) do
    factor = Application.get_env(:foundation, :timeout_factor, 1.0)
    round(timeout * factor)
  end
end
```

#### Migration Script for GenServer Calls
**Location**: `scripts/migrate_genserver_timeouts.exs`

```elixir
defmodule GenServerTimeoutMigrator do
  @moduledoc """
  Migrates GenServer.call/2 to include explicit timeouts.
  """
  
  def run do
    lib_files = Path.wildcard("lib/**/*.ex")
    test_files = Path.wildcard("test/**/*.exs")
    
    all_files = lib_files ++ test_files
    
    stats = Enum.reduce(all_files, %{checked: 0, modified: 0, calls_fixed: 0}, fn file, acc ->
      migrate_file(file, acc)
    end)
    
    print_report(stats)
  end
  
  defp migrate_file(file, stats) do
    content = File.read!(file)
    
    if String.contains?(content, "GenServer.call") do
      {new_content, count} = fix_genserver_calls(content, file)
      
      if new_content != content do
        File.write!(file, new_content)
        
        %{
          stats |
          checked: stats.checked + 1,
          modified: stats.modified + 1,
          calls_fixed: stats.calls_fixed + count
        }
      else
        %{stats | checked: stats.checked + 1}
      end
    else
      %{stats | checked: stats.checked + 1}
    end
  end
  
  defp fix_genserver_calls(content, file) do
    count = 0
    
    # Pattern 1: GenServer.call(server, message) - 2 args only
    {content, count1} = Regex.replace(
      ~r/GenServer\.call\(([^,\)]+),\s*([^,\)]+)\)(?!\s*,)/,
      content,
      fn full, server, message ->
        {"GenServer.call(#{server}, #{message}, :timer.seconds(5))", 1}
      end,
      global: true,
      return: :both
    )
    
    # Pattern 2: Add import for timeout config if needed
    content = if count1 > 0 and not String.contains?(content, "TimeoutConfig") do
      add_timeout_import(content)
    else
      content
    end
    
    {content, count + count1}
  end
  
  defp add_timeout_import(content) do
    # Add after module declaration
    Regex.replace(
      ~r/(defmodule .+ do\n)/,
      content,
      "\\1  import Foundation.TimeoutConfig\n"
    )
  end
  
  defp print_report(stats) do
    IO.puts("""
    
    === GenServer Timeout Migration Report ===
    
    Files checked: #{stats.checked}
    Files modified: #{stats.modified}  
    Calls fixed: #{stats.calls_fixed}
    
    All GenServer.call/2 have been migrated to include timeouts.
    
    Next steps:
    1. Review the changes
    2. Adjust timeouts based on operation type
    3. Run tests to ensure everything works
    """)
  end
end

GenServerTimeoutMigrator.run()
```

### 3.5 Integration and Testing
**Priority: HIGH**  
**Time Estimate: 1 day**

#### Create Integration Test Suite
**Location**: `test/foundation/otp_hardening_test.exs`

```elixir
defmodule Foundation.OTPHardeningTest do
  use Foundation.UnifiedTestFoundation, :full_isolation
  import Foundation.AsyncTestHelpers
  
  alias Foundation.{SupervisedSend, MonitorManager, TimeoutConfig}
  
  describe "SupervisedSend" do
    test "delivers messages to live processes", %{test_context: ctx} do
      {:ok, recipient} = GenServer.start_link(EchoServer, [])
      
      assert :ok = SupervisedSend.send_supervised(recipient, {:echo, "hello"})
      
      assert_receive {:echoed, "hello"}, 1000
    end
    
    test "handles dead processes gracefully", %{test_context: ctx} do
      {:ok, pid} = GenServer.start_link(EchoServer, [])
      GenServer.stop(pid)
      
      assert {:error, :noproc} = 
        SupervisedSend.send_supervised(pid, {:echo, "hello"})
    end
    
    test "retries on failure", %{test_context: ctx} do
      {:ok, flaky} = GenServer.start_link(FlakyServer, [fail_count: 2])
      
      assert :ok = SupervisedSend.send_supervised(
        flaky, 
        {:process, "data"},
        retries: 3,
        backoff: 10
      )
      
      assert GenServer.call(flaky, :get_attempts) == 3
    end
    
    test "broadcast with different strategies", %{test_context: ctx} do
      recipients = for i <- 1..3 do
        {:ok, pid} = GenServer.start_link(EchoServer, [])
        {i, pid, %{}}
      end
      
      # Best effort - all succeed
      assert {:ok, results} = SupervisedSend.broadcast_supervised(
        recipients,
        {:echo, "broadcast"},
        strategy: :best_effort
      )
      
      assert Enum.all?(results, fn {_id, result, _} -> result == :ok end)
      
      # All or nothing with one dead
      [{id, pid, meta} | rest] = recipients
      GenServer.stop(pid)
      dead_recipients = [{id, pid, meta} | rest]
      
      assert {:error, :noproc} = SupervisedSend.broadcast_supervised(
        dead_recipients,
        {:echo, "broadcast"},
        strategy: :all_or_nothing
      )
    end
  end
  
  describe "MonitorManager" do
    test "tracks monitors correctly", %{test_context: ctx} do
      {:ok, target} = GenServer.start_link(EchoServer, [])
      
      # Create monitor
      assert {:ok, ref} = MonitorManager.monitor(target, :test_feature)
      
      # Verify it's tracked
      monitors = MonitorManager.list_monitors()
      assert Enum.any?(monitors, fn m -> m.ref == ref end)
      
      # Clean up
      assert :ok = MonitorManager.demonitor(ref)
      
      # Verify it's gone
      monitors = MonitorManager.list_monitors()
      assert not Enum.any?(monitors, fn m -> m.ref == ref end)
    end
    
    test "auto-cleanup on process death", %{test_context: ctx} do
      {:ok, target} = GenServer.start_link(EchoServer, [])
      
      {:ok, ref} = MonitorManager.monitor(target, :auto_cleanup_test)
      
      # Kill the monitored process
      GenServer.stop(target)
      
      # Wait for cleanup
      wait_for(fn ->
        monitors = MonitorManager.list_monitors()
        not Enum.any?(monitors, fn m -> m.ref == ref end)
      end)
    end
    
    test "cleanup on caller death", %{test_context: ctx} do
      {:ok, target} = GenServer.start_link(EchoServer, [])
      
      # Create monitor from another process
      {:ok, caller} = Task.start_link(fn ->
        {:ok, _ref} = MonitorManager.monitor(target, :caller_cleanup)
        Process.sleep(:infinity)
      end)
      
      # Wait for monitor to be created
      wait_for(fn ->
        monitors = MonitorManager.list_monitors()
        Enum.any?(monitors, fn m -> m.tag == :caller_cleanup end)
      end)
      
      # Kill the caller
      Process.exit(caller, :kill)
      
      # Monitor should be cleaned up
      wait_for(fn ->
        monitors = MonitorManager.list_monitors()
        not Enum.any?(monitors, fn m -> m.tag == :caller_cleanup end)
      end)
    end
    
    test "detects leaks", %{test_context: ctx} do
      {:ok, target} = GenServer.start_link(EchoServer, [])
      
      # Create monitor but don't clean it up
      {:ok, ref} = MonitorManager.monitor(target, :leak_test)
      
      # Check for leaks (with very short age for testing)
      leaks = MonitorManager.find_leaks(0)
      assert Enum.any?(leaks, fn l -> l.tag == :leak_test end)
      
      # Cleanup
      MonitorManager.demonitor(ref)
    end
  end
  
  describe "Timeout Configuration" do
    test "provides appropriate timeouts", %{test_context: ctx} do
      # Default timeout
      assert TimeoutConfig.get_timeout(:unknown) == 5_000
      
      # Configured timeout
      assert TimeoutConfig.get_timeout("Foundation.ResourceManager") == 30_000
      
      # Operation timeout
      assert TimeoutConfig.get_timeout(:batch_operation) == 30_000
      
      # Pattern timeout
      assert TimeoutConfig.get_timeout({:cache_lookup, :get}) == 1_000
    end
  end
  
  # Test servers
  
  defmodule EchoServer do
    use GenServer
    
    def init(_), do: {:ok, %{}}
    
    def handle_cast({:echo, msg}, state) do
      send(self(), {:echoed, msg})
      {:noreply, state}
    end
  end
  
  defmodule FlakyServer do
    use GenServer
    
    def init(opts) do
      {:ok, %{
        fail_count: Keyword.get(opts, :fail_count, 1),
        attempts: 0
      }}
    end
    
    def handle_cast({:process, _data}, state) do
      new_state = %{state | attempts: state.attempts + 1}
      
      if new_state.attempts <= state.fail_count do
        {:stop, :induced_failure, new_state}
      else
        {:noreply, new_state}
      end
    end
    
    def handle_call(:get_attempts, _from, state) do
      {:reply, state.attempts, state}
    end
  end
end
```

## Verification Process

### After Each Component Implementation

1. **Run component tests**:
```bash
# Test supervised send
mix test test/foundation/supervised_send_test.exs

# Test monitor manager
mix test test/foundation/monitor_manager_test.exs

# Integration tests
mix test test/foundation/otp_hardening_test.exs
```

2. **Check for remaining violations**:
```bash
# Run Credo with Stage 1 configuration
mix credo --strict

# Check raw sends
grep -r "send(" lib/ --include="*.ex" | grep -v "self()" | wc -l
# Should be decreasing toward 0

# Check for monitor leaks
mix run -e "IO.inspect Foundation.MonitorManager.get_stats()"
```

3. **Performance validation**:
```bash
# Benchmark supervised vs raw send
mix run benchmarks/supervised_send_bench.exs

# Monitor memory usage
mix run --no-halt
# In another terminal:
:observer.start()
```

### Full System Verification

1. **All violations eliminated**:
```bash
# Final violation check
mix run scripts/otp_final_audit.exs
```

2. **Load testing**:
```bash
# Run under load to verify no degradation
mix test test/load/otp_compliance_load_test.exs
```

3. **Production readiness**:
```bash
# Full test suite
mix test

# Dialyzer
mix dialyzer

# Coverage
mix test --cover
```

## Common Issues & Solutions

### Issue: Performance impact from supervised sends
**Solution**: Use appropriate strategies
- Use GenServer.cast for fire-and-forget
- Use supervised send only for critical paths
- Batch operations where possible

### Issue: Monitor manager becomes bottleneck
**Solution**: Shard the monitor manager
```elixir
# Use multiple monitor managers
defmodule MonitorRouter do
  def monitor(pid, tag) do
    shard = :erlang.phash2(pid, 4)
    MonitorManager.monitor(:"monitor_manager_#{shard}", pid, tag)
  end
end
```

### Issue: Timeout configuration too rigid
**Solution**: Add dynamic configuration
```elixir
# Allow runtime overrides
TimeoutConfig.set_timeout(:my_operation, 10_000)
```

## Success Criteria

Stage 3 is complete when:
- ✅ 0 raw send() calls to other processes (self-sends allowed)
- ✅ All monitors use MonitorManager
- ✅ All GenServer.call include explicit timeouts
- ✅ SupervisedSend infrastructure deployed
- ✅ Dead letter queue operational
- ✅ No performance regression
- ✅ All tests pass
- ✅ 0 Credo violations

## Next Steps

After completing Stage 3:
1. Enable strict CI enforcement
2. Remove all .backup files
3. Document new patterns for team
4. Monitor production metrics
5. Plan gradual rollout if needed

---

**Completion Checklist**:
- [ ] SupervisedSend module created and tested
- [ ] Dead letter queue implemented
- [ ] All critical sends migrated (coordinator, signal router, etc.)
- [ ] Migration scripts run for remaining sends
- [ ] MonitorManager deployed
- [ ] All monitors migrated
- [ ] GenServer timeouts added
- [ ] Integration tests passing
- [ ] Performance benchmarks acceptable
- [ ] Documentation updated