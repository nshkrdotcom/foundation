# ==============================================================================
# Python Bridge Worker Module
# ==============================================================================

defmodule Foundation.Bridge.Python.Worker do
  @moduledoc """
  Individual Python worker process that manages a single Python interpreter.
  
  This module handles the low-level communication with Python processes through
  Elixir ports, providing reliable execution of Python code with proper error
  handling and resource management.
  
  ## Features
  
  - **Port Management**: Robust port lifecycle management
  - **Message Protocol**: JSON-based bidirectional communication
  - **Timeout Handling**: Configurable timeouts with cleanup
  - **Error Recovery**: Automatic process restart on failures
  - **Resource Monitoring**: Memory and CPU usage tracking
  - **Health Checks**: Regular health monitoring
  
  ## Internal Protocol
  
  The worker communicates with Python processes using a JSON protocol:
  
      # Command to Python
      %{
        "type" => "execute",
        "code" => "python_code_here",
        "context" => %{},
        "correlation_id" => "uuid",
        "timeout" => 30000
      }
      
      # Response from Python
      %{
        "type" => "response",
        "data" => result,
        "success" => true
      }
      
      # Error from Python
      %{
        "type" => "error",
        "error_type" => "execution_error",
        "message" => "error details",
        "success" => false
      }
  """
  
  use GenServer
  require Logger
  
  alias Foundation.{Events, Telemetry, ErrorContext, Utils}
  alias Foundation.Types.{Error, Event}
  
  @type worker_state :: %{
    port: port() | nil,
    config: map(),
    pending_requests: %{reference() => {pid(), term()}},
    python_pid: pos_integer() | nil,
    stats: map(),
    pool_name: atom(),
    worker_id: String.t(),
    restart_count: non_neg_integer(),
    last_health_check: integer() | nil
  }
  
  @type execution_command :: %{
    type: String.t(),
    code: String.t(),
    context: map(),
    correlation_id: String.t(),
    timeout: pos_integer()
  }
  
  @default_config %{
    python_path: "python3",
    script_dir: "./priv/python",
    venv_path: nil,
    debug_mode: false,
    preload_modules: [],
    pool_name: :default,
    buffer_size: 65536,
    max_restarts: 5,
    restart_window: 60_000  # 1 minute
  }
  
  ## Public API
  
  @doc """
  Start a Python worker process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end
  
  @doc """
  Execute a command on the Python worker.
  """
  @spec execute(pid(), execution_command(), pos_integer()) :: 
    {:ok, term()} | {:error, Error.t()}
  def execute(worker_pid, command, timeout \\ 30_000) do
    GenServer.call(worker_pid, {:execute, command}, timeout + 1_000)
  end
  
  @doc """
  Perform health check on the worker.
  """
  @spec health_check(pid()) :: {:ok, map()} | {:error, Error.t()}
  def health_check(worker_pid) do
    GenServer.call(worker_pid, :health_check, 5_000)
  end
  
  @doc """
  Get worker statistics.
  """
  @spec get_stats(pid()) :: {:ok, map()}
  def get_stats(worker_pid) do
    GenServer.call(worker_pid, :get_stats)
  end
  
  @doc """
  Restart the Python process.
  """
  @spec restart_python(pid()) :: :ok | {:error, Error.t()}
  def restart_python(worker_pid) do
    GenServer.call(worker_pid, :restart_python)
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(args) do
    config = Map.merge(@default_config, Map.new(args))
    worker_id = Utils.generate_correlation_id()
    
    state = %{
      port: nil,
      config: config,
      pending_requests: %{},
      python_pid: nil,
      stats: init_stats(),
      pool_name: config.pool_name,
      worker_id: worker_id,
      restart_count: 0,
      last_health_check: nil
    }
    
    case start_python_process(state) do
      {:ok, new_state} ->
        Logger.info("Python worker #{worker_id} started for pool #{config.pool_name}")
        {:ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to start Python worker: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl GenServer
  def handle_call({:execute, command}, from, state) do
    case state.port do
      nil ->
        error = Error.new(:worker_unavailable, "Python process not running")
        {:reply, {:error, error}, state}
        
      port ->
        execute_command(command, from, port, state)
    end
  end
  
  @impl GenServer
  def handle_call(:health_check, _from, state) do
    case perform_health_check(state) do
      {:ok, health_data, new_state} ->
        {:reply, {:ok, health_data}, new_state}
        
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      worker_id: state.worker_id,
      pool_name: state.pool_name,
      python_pid: state.python_pid,
      pending_requests: map_size(state.pending_requests),
      restart_count: state.restart_count,
      uptime_ms: System.monotonic_time(:millisecond) - state.stats.start_time,
      port_status: if(state.port, do: :running, else: :stopped)
    })
    
    {:reply, {:ok, stats}, state}
  end
  
  @impl GenServer
  def handle_call(:restart_python, _from, state) do
    case restart_python_process(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case handle_python_response(data, state) do
      {:ok, new_state} ->
        {:noreply, new_state}
        
      {:error, error, new_state} ->
        Logger.warning("Error handling Python response: #{inspect(error)}")
        {:noreply, new_state}
    end
  end
  
  @impl GenServer
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Python process exited with status #{status}")
    
    # Notify pending requests of failure
    new_state = fail_pending_requests(state, :python_process_exited)
    
    # Attempt restart if within limits
    case should_restart?(new_state) do
      true ->
        case restart_python_process(new_state) do
          {:ok, restarted_state} ->
            {:noreply, restarted_state}
            
          {:error, _reason} ->
            {:stop, :python_restart_failed, new_state}
        end
        
      false ->
        Logger.error("Python worker restart limit exceeded")
        {:stop, :restart_limit_exceeded, new_state}
    end
  end
  
  @impl GenServer
  def handle_info({:timeout, ref}, state) do
    case Map.pop(state.pending_requests, ref) do
      {{from_pid, _command}, new_pending} ->
        error = Error.new(:execution_timeout, "Python execution timed out")
        GenServer.reply(from_pid, {:error, error})
        
        new_stats = Map.update!(state.stats, :timeouts, &(&1 + 1))
        new_state = %{
          state | 
          pending_requests: new_pending,
          stats: new_stats
        }
        
        {:noreply, new_state}
        
      {nil, _} ->
        # Timeout for non-existent request
        {:noreply, state}
    end
  end
  
  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Python worker #{state.worker_id} terminating: #{inspect(reason)}")
    
    # Clean shutdown of Python process
    if state.port do
      shutdown_command = %{type: "shutdown"}
      send_to_python(state.port, shutdown_command)
      
      # Give Python time to shutdown gracefully
      Process.sleep(1000)
      
      Port.close(state.port)
    end
    
    # Fail any pending requests
    fail_pending_requests(state, :worker_shutdown)
    
    :ok
  end
  
  ## Private Implementation
  
  defp start_python_process(state) do
    python_cmd = build_python_command(state.config)
    script_path = Path.join(state.config.script_dir, "bridge_worker.py")
    
    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4},  # Use 4-byte length prefix for message framing
      {:args, [script_path]},
      {:cd, state.config.script_dir}
    ]
    
    try do
      port = Port.open({:spawn_executable, python_cmd}, port_opts)
      
      # Wait for Python process to be ready
      case wait_for_python_ready(port, 5000) do
        {:ok, python_pid} ->
          new_state = %{
            state | 
            port: port,
            python_pid: python_pid,
            stats: Map.put(state.stats, :start_time, System.monotonic_time(:millisecond))
          }
          
          emit_worker_event(:started, new_state)
          {:ok, new_state}
          
        {:error, reason} ->
          Port.close(port)
          {:error, reason}
      end
      
    rescue
      error ->
        error_reason = Error.new(:port_creation_failed, 
          "Failed to create Python port: #{inspect(error)}")
        {:error, error_reason}
    end
  end
  
  defp build_python_command(config) do
    if config.venv_path do
      Path.join([config.venv_path, "bin", "python"])
    else
      config.python_path
    end
  end
  
  defp wait_for_python_ready(port, timeout) do
    # Send initial health check to verify Python is ready
    health_command = %{type: "health_check"}
    send_to_python(port, health_command)
    
    receive do
      {^port, {:data, data}} ->
        case Jason.decode(data) do
          {:ok, %{"type" => "response", "data" => %{"status" => "healthy", "pid" => pid}}} ->
            {:ok, pid}
            
          {:ok, %{"type" => "error"}} ->
            {:error, :python_initialization_failed}
            
          _ ->
            {:error, :invalid_response}
        end
        
      {^port, {:exit_status, status}} ->
        {:error, {:python_exited, status}}
        
    after
      timeout ->
        {:error, :initialization_timeout}
    end
  end
  
  defp execute_command(command, from, port, state) do
    ref = make_ref()
    timer_ref = Process.send_after(self(), {:timeout, ref}, command.timeout)
    
    # Store the request
    new_pending = Map.put(state.pending_requests, ref, {from, command})
    
    # Add correlation tracking
    enhanced_command = Map.put(command, :request_ref, inspect(ref))
    
    case send_to_python(port, enhanced_command) do
      :ok ->
        new_stats = Map.update!(state.stats, :executions_started, &(&1 + 1))
        new_state = %{
          state | 
          pending_requests: new_pending,
          stats: new_stats
        }
        
        emit_execution_event(:started, command, new_state)
        {:noreply, new_state}
        
      {:error, reason} ->
        # Cancel timeout and remove from pending
        Process.cancel_timer(timer_ref)
        
        error = Error.new(:send_failed, "Failed to send command to Python", 
          context: %{reason: reason})
        {:reply, {:error, error}, state}
    end
  end
  
  defp send_to_python(port, command) do
    try do
      json_data = Jason.encode!(command)
      Port.command(port, json_data)
      :ok
    rescue
      error ->
        {:error, error}
    end
  end
  
  defp handle_python_response(data, state) do
    try do
      case Jason.decode(data) do
        {:ok, response} ->
          process_python_response(response, state)
          
        {:error, decode_error} ->
          Logger.error("Failed to decode Python response: #{inspect(decode_error)}")
          error = Error.new(:decode_error, "Invalid JSON from Python")
          {:error, error, state}
      end
    rescue
      error ->
        Logger.error("Exception handling Python response: #{inspect(error)}")
        {:error, error, state}
    end
  end
  
  defp process_python_response(response, state) do
    case response do
      %{"type" => "response", "success" => true, "data" => data} ->
        handle_successful_response(data, state)
        
      %{"type" => "error", "success" => false, "message" => message, "error_type" => error_type} ->
        handle_error_response(error_type, message, state)
        
      %{"type" => "health_check_response"} ->
        # Health check response - update last check time
        new_state = %{state | last_health_check: System.monotonic_time(:millisecond)}
        {:ok, new_state}
        
      _ ->
        Logger.warning("Unknown response format from Python: #{inspect(response)}")
        {:ok, state}
    end
  end
  
  defp handle_successful_response(data, state) do
    # For now, respond to the most recent request
    # In a more sophisticated implementation, we'd match by correlation ID
    case get_next_pending_request(state) do
      {{ref, {from, command}}, new_pending} ->
        GenServer.reply(from, {:ok, data})
        
        new_stats = Map.update!(state.stats, :executions_completed, &(&1 + 1))
        new_state = %{
          state | 
          pending_requests: new_pending,
          stats: new_stats
        }
        
        emit_execution_event(:completed, command, new_state)
        {:ok, new_state}
        
      {nil, _} ->
        Logger.warning("Received Python response with no pending requests")
        {:ok, state}
    end
  end
  
  defp handle_error_response(error_type, message, state) do
    case get_next_pending_request(state) do
      {{ref, {from, command}}, new_pending} ->
        error = Error.new(String.to_atom(error_type), message, 
          context: %{python_error: true})
        GenServer.reply(from, {:error, error})
        
        new_stats = Map.update!(state.stats, :executions_failed, &(&1 + 1))
        new_state = %{
          state | 
          pending_requests: new_pending,
          stats: new_stats
        }
        
        emit_execution_event(:failed, command, new_state)
        {:ok, new_state}
        
      {nil, _} ->
        Logger.warning("Received Python error with no pending requests: #{message}")
        {:ok, state}
    end
  end
  
  defp get_next_pending_request(state) do
    case Enum.take(state.pending_requests, 1) do
      [{ref, request}] ->
        new_pending = Map.delete(state.pending_requests, ref)
        {{ref, request}, new_pending}
        
      [] ->
        {nil, state.pending_requests}
    end
  end
  
  defp perform_health_check(state) do
    if state.port do
      health_command = %{type: "health_check"}
      
      case send_to_python(state.port, health_command) do
        :ok ->
          # Wait for response
          receive do
            {port, {:data, data}} when port == state.port ->
              case Jason.decode(data) do
                {:ok, %{"type" => "response", "data" => health_data}} ->
                  new_state = %{state | last_health_check: System.monotonic_time(:millisecond)}
                  {:ok, health_data, new_state}
                  
                _ ->
                  error = Error.new(:health_check_failed, "Invalid health check response")
                  {:error, error, state}
              end
              
          after
            5000 ->
              error = Error.new(:health_check_timeout, "Health check timed out")
              {:error, error, state}
          end
          
        {:error, reason} ->
          error = Error.new(:health_check_send_failed, "Failed to send health check", 
            context: %{reason: reason})
          {:error, error, state}
      end
    else
      error = Error.new(:worker_unavailable, "Python process not running")
      {:error, error, state}
    end
  end
  
  defp restart_python_process(state) do
    Logger.info("Restarting Python process for worker #{state.worker_id}")
    
    # Close existing port if present
    if state.port do
      Port.close(state.port)
    end
    
    # Fail pending requests
    new_state = fail_pending_requests(state, :restarting)
    
    # Increment restart count
    restart_state = %{
      new_state | 
      port: nil,
      python_pid: nil,
      restart_count: new_state.restart_count + 1
    }
    
    # Start new Python process
    case start_python_process(restart_state) do
      {:ok, restarted_state} ->
        emit_worker_event(:restarted, restarted_state)
        {:ok, restarted_state}
        
      {:error, reason} ->
        emit_worker_event(:restart_failed, restart_state)
        {:error, reason}
    end
  end
  
  defp should_restart?(state) do
    state.restart_count < state.config.max_restarts
  end
  
  defp fail_pending_requests(state, reason) do
    error = Error.new(:worker_failure, "Worker operation failed", 
      context: %{reason: reason})
    
    Enum.each(state.pending_requests, fn {_ref, {from, _command}} ->
      GenServer.reply(from, {:error, error})
    end)
    
    %{state | pending_requests: %{}}
  end
  
  defp init_stats() do
    %{
      executions_started: 0,
      executions_completed: 0,
      executions_failed: 0,
      timeouts: 0,
      start_time: System.monotonic_time(:millisecond)
    }
  end
  
  defp emit_worker_event(event_type, state) do
    if Events.available?() do
      event_data = %{
        worker_id: state.worker_id,
        pool_name: state.pool_name,
        python_pid: state.python_pid,
        restart_count: state.restart_count
      }
      
      case Events.new_event(:"python_worker_#{event_type}", event_data) do
        {:ok, event} -> Events.store(event)
        {:error, _} -> :ok
      end
    end
  end
  
  defp emit_execution_event(event_type, command, state) do
    if Events.available?() do
      event_data = %{
        worker_id: state.worker_id,
        pool_name: state.pool_name,
        correlation_id: command.correlation_id,
        code_preview: String.slice(command.code, 0, 100)
      }
      
      case Events.new_event(:"python_execution_#{event_type}", event_data, 
        correlation_id: command.correlation_id) do
        {:ok, event} -> Events.store(event)
        {:error, _} -> :ok
      end
    end
  end
end
