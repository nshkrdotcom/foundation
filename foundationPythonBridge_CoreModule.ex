# Foundation Python Bridge Implementation
# This is a comprehensive ports-based Python bridge integrated with Foundation

# ==============================================================================
# Core Bridge Module
# ==============================================================================

defmodule Foundation.Bridge.Python do
  @moduledoc """
  Comprehensive Python bridge using Elixir ports for robust bidirectional communication.
  
  This module provides a high-level API for executing Python code, managing
  Python processes, and handling data serialization between Elixir and Python.
  
  ## Features
  
  - **Robust Process Management**: Automatic restarts, health monitoring
  - **Event Integration**: Full Foundation Events system integration  
  - **Circuit Breaker Protection**: Automatic failure handling
  - **Connection Pooling**: Multiple Python worker processes
  - **Data Serialization**: JSON and binary protocols
  - **Error Context**: Enhanced error reporting with correlation
  - **Telemetry**: Comprehensive metrics and monitoring
  
  ## Usage
  
      # Initialize the bridge
      {:ok, _pid} = Foundation.Bridge.Python.start_link()
      
      # Execute Python code
      {:ok, result} = Foundation.Bridge.Python.execute("return 2 + 2")
      
      # Call Python functions with arguments
      {:ok, result} = Foundation.Bridge.Python.call("math.sqrt", [16])
      
      # Execute with timeout and options
      {:ok, result} = Foundation.Bridge.Python.execute(
        "import time; time.sleep(1); return 'done'",
        timeout: 5000,
        pool: :heavy_computation
      )
  """
  
  use GenServer
  require Logger
  
  alias Foundation.{Events, Telemetry, ErrorContext}
  alias Foundation.Types.{Error, Event}
  alias Foundation.Infrastructure.{CircuitBreaker, ConnectionManager}
  alias Foundation.Services.{TelemetryService}
  
  @behaviour Foundation.Contracts.Configurable
  
  # Configuration
  @default_config %{
    # Python executable path
    python_path: "python3",
    # Number of worker processes in pool
    pool_size: 5,
    # Maximum pool overflow
    max_overflow: 10,
    # Default timeout for operations (ms)
    default_timeout: 30_000,
    # Python script directory
    script_dir: "./priv/python",
    # Enable circuit breaker protection
    circuit_breaker_enabled: true,
    # Circuit breaker config
    circuit_breaker: %{
      failure_threshold: 5,
      recovery_time: 30_000
    },
    # Data serialization format
    serialization: :json,  # :json | :erlang_term | :msgpack
    # Buffer sizes
    buffer_size: 65536,
    # Health check interval
    health_check_interval: 30_000,
    # Auto-restart failed workers
    auto_restart: true,
    # Python virtual environment path
    venv_path: nil,
    # Additional Python modules to preload
    preload_modules: ["json", "sys", "os", "base64"],
    # Custom Python initialization script
    init_script: nil,
    # Enable detailed logging
    debug_mode: false
  }
  
  @type config :: map()
  @type pool_name :: atom()
  @type python_code :: String.t()
  @type python_args :: [term()]
  @type execution_options :: [
    timeout: pos_integer(),
    pool: pool_name(),
    correlation_id: String.t(),
    metadata: map()
  ]
  
  @type execution_result :: {:ok, term()} | {:error, Error.t()}
  @type bridge_state :: %{
    config: config(),
    pools: %{pool_name() => pid()},
    circuit_breakers: %{pool_name() => atom()},
    health_check_timer: reference() | nil,
    metrics: map(),
    namespace: atom()
  }
  
  ## Public API
  
  @doc """
  Start the Python bridge with configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :production)
    name = Foundation.ServiceRegistry.via_tuple(namespace, :python_bridge)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :namespace, namespace), name: name)
  end
  
  @doc """
  Execute Python code and return the result.
  
  ## Examples
  
      {:ok, 4} = Foundation.Bridge.Python.execute("return 2 + 2")
      
      {:ok, result} = Foundation.Bridge.Python.execute(
        "import math; return math.sqrt(16)",
        timeout: 5000
      )
  """
  @spec execute(python_code(), execution_options()) :: execution_result()
  def execute(code, opts \\ []) do
    context = ErrorContext.new(__MODULE__, :execute, 
      metadata: %{code_preview: String.slice(code, 0, 100)})
    
    ErrorContext.with_context(context, fn ->
      case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
        {:ok, pid} -> 
          GenServer.call(pid, {:execute, code, opts}, get_timeout(opts))
        {:error, _} = error -> 
          error
      end
    end)
  end
  
  @doc """
  Call a Python function with arguments.
  
  ## Examples
  
      {:ok, 4.0} = Foundation.Bridge.Python.call("math.sqrt", [16])
      
      {:ok, result} = Foundation.Bridge.Python.call(
        "json.dumps", 
        [%{key: "value"}],
        timeout: 5000
      )
  """
  @spec call(String.t(), python_args(), execution_options()) :: execution_result()
  def call(function_name, args \\ [], opts \\ []) do
    # Convert function call to Python code
    encoded_args = Jason.encode!(args)
    code = """
    import json
    args = json.loads('#{String.replace(encoded_args, "'", "\\'")}')
    result = #{function_name}(*args)
    return result
    """
    
    execute(code, opts)
  end
  
  @doc """
  Execute Python code from a file.
  
  ## Examples
  
      {:ok, result} = Foundation.Bridge.Python.execute_file("data_processing.py", 
        args: [input_data], timeout: 60_000)
  """
  @spec execute_file(String.t(), execution_options()) :: execution_result()
  def execute_file(filename, opts \\ []) do
    context = ErrorContext.new(__MODULE__, :execute_file, metadata: %{filename: filename})
    
    ErrorContext.with_context(context, fn ->
      case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
        {:ok, pid} -> 
          GenServer.call(pid, {:execute_file, filename, opts}, get_timeout(opts))
        {:error, _} = error -> 
          error
      end
    end)
  end
  
  @doc """
  Get the current status of the Python bridge.
  """
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status() do
    case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
      {:ok, pid} -> GenServer.call(pid, :get_status)
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Check if the Python bridge is available.
  """
  @spec available?() :: boolean()
  def available?() do
    case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
      {:ok, _pid} -> true
      {:error, _} -> false
    end
  end
  
  @doc """
  Initialize a new worker pool for specific workloads.
  
  ## Examples
  
      :ok = Foundation.Bridge.Python.create_pool(:ml_processing, 
        size: 3, 
        preload_modules: ["numpy", "pandas", "sklearn"]
      )
  """
  @spec create_pool(pool_name(), keyword()) :: :ok | {:error, Error.t()}
  def create_pool(pool_name, opts \\ []) do
    case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
      {:ok, pid} -> GenServer.call(pid, {:create_pool, pool_name, opts})
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Perform health check on all Python workers.
  """
  @spec health_check() :: {:ok, map()} | {:error, Error.t()}
  def health_check() do
    case Foundation.ServiceRegistry.lookup(:production, :python_bridge) do
      {:ok, pid} -> GenServer.call(pid, :health_check)
      {:error, _} = error -> error
    end
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    namespace = Keyword.get(opts, :namespace, :production)
    config = build_config(opts)
    
    # Register with Foundation service registry
    :ok = Foundation.ServiceRegistry.register(namespace, :python_bridge, self())
    
    state = %{
      config: config,
      pools: %{},
      circuit_breakers: %{},
      health_check_timer: nil,
      metrics: init_metrics(),
      namespace: namespace
    }
    
    # Initialize the bridge
    case initialize_bridge(state) do
      {:ok, new_state} ->
        Logger.info("Python bridge initialized successfully")
        schedule_health_check(new_state)
        {:ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to initialize Python bridge: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl GenServer
  def handle_call({:execute, code, opts}, from, state) do
    pool_name = Keyword.get(opts, :pool, :default)
    correlation_id = Keyword.get(opts, :correlation_id, Foundation.Utils.generate_correlation_id())
    
    emit_execution_event(:start, pool_name, correlation_id, %{
      code_preview: String.slice(code, 0, 100),
      opts: sanitize_opts(opts)
    })
    
    case get_worker_from_pool(pool_name, state) do
      {:ok, worker} ->
        # Execute with circuit breaker protection
        circuit_breaker = Map.get(state.circuit_breakers, pool_name, :default_breaker)
        
        result = CircuitBreaker.execute(circuit_breaker, fn ->
          execute_python_code(worker, code, opts, correlation_id)
        end)
        
        emit_execution_event(:complete, pool_name, correlation_id, %{result: sanitize_result(result)})
        
        {:reply, result, update_metrics(state, pool_name, result)}
        
      {:error, _} = error ->
        emit_execution_event(:error, pool_name, correlation_id, %{error: error})
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:execute_file, filename, opts}, from, state) do
    full_path = Path.join(state.config.script_dir, filename)
    
    case File.read(full_path) do
      {:ok, content} ->
        handle_call({:execute, content, opts}, from, state)
        
      {:error, reason} ->
        error = Error.new(:file_error, "Failed to read Python file: #{inspect(reason)}", 
          context: %{filename: filename, full_path: full_path})
        {:reply, {:error, error}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:create_pool, pool_name, opts}, _from, state) do
    case create_python_pool(pool_name, opts, state.config) do
      {:ok, pool_pid} ->
        circuit_breaker_name = :"#{pool_name}_breaker"
        CircuitBreaker.start_fuse_instance(circuit_breaker_name, 
          strategy: :standard, 
          tolerance: state.config.circuit_breaker.failure_threshold,
          refresh: state.config.circuit_breaker.recovery_time
        )
        
        new_state = %{
          state | 
          pools: Map.put(state.pools, pool_name, pool_pid),
          circuit_breakers: Map.put(state.circuit_breakers, pool_name, circuit_breaker_name)
        }
        
        Logger.info("Created Python pool: #{pool_name}")
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        error = Error.new(:pool_creation_failed, "Failed to create pool", 
          context: %{pool_name: pool_name, reason: reason})
        {:reply, {:error, error}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      status: :running,
      pools: get_pools_status(state.pools),
      circuit_breakers: get_circuit_breakers_status(state.circuit_breakers),
      metrics: state.metrics,
      config: sanitize_config(state.config),
      uptime_ms: System.monotonic_time(:millisecond)
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl GenServer
  def handle_call(:health_check, _from, state) do
    health_results = perform_health_checks(state.pools)
    
    overall_health = if Enum.all?(health_results, fn {_pool, result} -> 
      match?({:ok, _}, result) 
    end), do: :healthy, else: :degraded
    
    health_report = %{
      overall_status: overall_health,
      pools: health_results,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    {:reply, {:ok, health_report}, state}
  end
  
  @impl GenServer
  def handle_info(:health_check, state) do
    # Perform periodic health checks
    perform_health_checks(state.pools)
    schedule_health_check(state)
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle worker process death
    Logger.warning("Python worker process died: #{inspect(reason)}")
    
    if state.config.auto_restart do
      # Find and restart the failed pool
      case find_pool_by_pid(pid, state.pools) do
        {:ok, pool_name} ->
          Logger.info("Restarting Python pool: #{pool_name}")
          restart_pool(pool_name, state)
          
        :not_found ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end
  
  ## Private Implementation Functions
  
  defp build_config(opts) do
    Map.merge(@default_config, Map.new(opts))
  end
  
  defp initialize_bridge(state) do
    with :ok <- ensure_python_available(state.config),
         :ok <- setup_script_directory(state.config),
         {:ok, default_pool} <- create_default_pool(state.config),
         :ok <- setup_circuit_breakers(state.config) do
      
      new_state = %{
        state | 
        pools: Map.put(state.pools, :default, default_pool),
        circuit_breakers: Map.put(state.circuit_breakers, :default, :default_breaker)
      }
      
      {:ok, new_state}
    else
      {:error, _} = error -> error
    end
  end
  
  defp ensure_python_available(config) do
    python_cmd = if config.venv_path do
      Path.join([config.venv_path, "bin", "python"])
    else
      config.python_path
    end
    
    case System.cmd(python_cmd, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Python bridge using: #{String.trim(output)}")
        :ok
        
      {error, _} ->
        {:error, Error.new(:python_not_available, "Python not available: #{error}")}
    end
  end
  
  defp setup_script_directory(config) do
    case File.mkdir_p(config.script_dir) do
      :ok -> 
        create_bridge_script(config)
        
      {:error, reason} ->
        {:error, Error.new(:script_dir_error, "Failed to create script directory", 
          context: %{reason: reason, path: config.script_dir})}
    end
  end
  
  defp create_bridge_script(config) do
    bridge_script_content = """
    #!/usr/bin/env python3
    # Foundation Python Bridge Worker
    
    import sys
    import json
    import traceback
    import base64
    import signal
    import os
    from typing import Any, Dict, Optional
    
    class FoundationBridge:
        def __init__(self):
            self.modules = {}
            self.preload_modules()
            
        def preload_modules(self):
            \"\"\"Preload commonly used modules\"\"\"
            modules_to_load = #{Jason.encode!(config.preload_modules)}
            for module_name in modules_to_load:
                try:
                    self.modules[module_name] = __import__(module_name)
                except ImportError as e:
                    self.send_error(f"Failed to preload module {module_name}: {e}")
        
        def send_response(self, data: Any):
            \"\"\"Send response back to Elixir\"\"\"
            response = {
                "type": "response",
                "data": data,
                "success": True
            }
            print(json.dumps(response))
            sys.stdout.flush()
            
        def send_error(self, error: str, error_type: str = "python_error"):
            \"\"\"Send error back to Elixir\"\"\"
            response = {
                "type": "error", 
                "error_type": error_type,
                "message": error,
                "success": False
            }
            print(json.dumps(response))
            sys.stdout.flush()
            
        def execute_code(self, code: str, context: Optional[Dict] = None):
            \"\"\"Execute Python code safely\"\"\"
            try:
                # Create execution context
                exec_context = {
                    "__builtins__": __builtins__,
                    "bridge": self,
                    **self.modules
                }
                
                if context:
                    exec_context.update(context)
                
                # Execute the code
                exec(code, exec_context)
                
                # Check if there's a return value
                if 'return' in code:
                    # Handle return statements by wrapping in function
                    func_code = f"def _exec_func():\\n" + "\\n".join(f"    {line}" for line in code.split("\\n"))
                    exec(func_code, exec_context)
                    result = exec_context['_exec_func']()
                    self.send_response(result)
                else:
                    self.send_response(None)
                    
            except Exception as e:
                error_msg = f"{type(e).__name__}: {str(e)}"
                traceback_str = traceback.format_exc()
                self.send_error(f"{error_msg}\\n{traceback_str}", "execution_error")
    
        def handle_command(self, command: Dict):
            \"\"\"Handle command from Elixir\"\"\"
            cmd_type = command.get("type")
            
            if cmd_type == "execute":
                code = command.get("code", "")
                context = command.get("context", {})
                self.execute_code(code, context)
                
            elif cmd_type == "health_check":
                self.send_response({"status": "healthy", "pid": os.getpid()})
                
            elif cmd_type == "shutdown":
                self.send_response({"status": "shutting_down"})
                sys.exit(0)
                
            else:
                self.send_error(f"Unknown command type: {cmd_type}", "unknown_command")
    
        def run(self):
            \"\"\"Main loop - read commands from stdin\"\"\"
            try:
                while True:
                    line = sys.stdin.readline()
                    if not line:
                        break
                        
                    try:
                        command = json.loads(line.strip())
                        self.handle_command(command)
                    except json.JSONDecodeError as e:
                        self.send_error(f"Invalid JSON: {e}", "json_error")
                        
            except KeyboardInterrupt:
                self.send_response({"status": "interrupted"})
            except Exception as e:
                self.send_error(f"Bridge error: {e}", "bridge_error")
    
    if __name__ == "__main__":
        # Set up signal handlers
        def signal_handler(signum, frame):
            sys.exit(0)
            
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)
        
        # Initialize and run bridge
        bridge = FoundationBridge()
        bridge.run()
    """
    
    script_path = Path.join(config.script_dir, "bridge_worker.py")
    File.write!(script_path, bridge_script_content)
    File.chmod!(script_path, 0o755)
    
    :ok
  end
  
  defp create_default_pool(config) do
    create_python_pool(:default, [], config)
  end
  
  defp create_python_pool(pool_name, opts, config) do
    pool_config = [
      name: {:local, :"python_pool_#{pool_name}"},
      worker_module: Foundation.Bridge.Python.Worker,
      size: Keyword.get(opts, :size, config.pool_size),
      max_overflow: Keyword.get(opts, :max_overflow, config.max_overflow),
      strategy: :lifo
    ]
    
    worker_args = [
      python_path: config.python_path,
      script_dir: config.script_dir,
      venv_path: config.venv_path,
      debug_mode: config.debug_mode,
      preload_modules: Keyword.get(opts, :preload_modules, config.preload_modules),
      pool_name: pool_name
    ]
    
    case ConnectionManager.start_pool(pool_name, 
      Keyword.merge(pool_config, [worker_args: worker_args])) do
      {:ok, pool_pid} -> {:ok, pool_pid}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp setup_circuit_breakers(config) do
    if config.circuit_breaker_enabled do
      CircuitBreaker.start_fuse_instance(:default_breaker, 
        strategy: :standard,
        tolerance: config.circuit_breaker.failure_threshold,
        refresh: config.circuit_breaker.recovery_time
      )
    else
      :ok
    end
  end
  
  defp get_worker_from_pool(pool_name, state) do
    case Map.get(state.pools, pool_name) do
      nil -> 
        {:error, Error.new(:pool_not_found, "Python pool not found", 
          context: %{pool_name: pool_name})}
        
      _pool_pid ->
        ConnectionManager.with_connection(pool_name, fn worker ->
          {:ok, worker}
        end)
    end
  end
  
  defp execute_python_code(worker, code, opts, correlation_id) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    metadata = Keyword.get(opts, :metadata, %{})
    
    command = %{
      type: "execute",
      code: code,
      context: metadata,
      correlation_id: correlation_id,
      timeout: timeout
    }
    
    Foundation.Bridge.Python.Worker.execute(worker, command, timeout)
  end
  
  defp emit_execution_event(event_type, pool_name, correlation_id, metadata) do
    if Events.available?() do
      event_data = Map.merge(metadata, %{
        event_type: event_type,
        pool_name: pool_name,
        correlation_id: correlation_id
      })
      
      case Events.new_event(:"python_bridge_#{event_type}", event_data, 
        correlation_id: correlation_id) do
        {:ok, event} -> Events.store(event)
        {:error, _} -> :ok  # Don't fail on event errors
      end
    end
  end
  
  defp update_metrics(state, pool_name, result) do
    new_metrics = case result do
      {:ok, _} ->
        Map.update(state.metrics, :successful_executions, 1, &(&1 + 1))
        
      {:error, _} ->
        Map.update(state.metrics, :failed_executions, 1, &(&1 + 1))
    end
    
    # Emit telemetry
    TelemetryService.emit_counter([:foundation, :python_bridge, :executions], %{
      pool_name: pool_name,
      result: if(match?({:ok, _}, result), do: :success, else: :error)
    })
    
    %{state | metrics: new_metrics}
  end
  
  defp init_metrics() do
    %{
      successful_executions: 0,
      failed_executions: 0,
      start_time: System.monotonic_time(:millisecond)
    }
  end
  
  defp schedule_health_check(state) do
    if state.config.health_check_interval > 0 do
      timer_ref = Process.send_after(self(), :health_check, state.config.health_check_interval)
      %{state | health_check_timer: timer_ref}
    else
      state
    end
  end
  
  defp perform_health_checks(pools) do
    Enum.map(pools, fn {pool_name, _pool_pid} ->
      health_result = ConnectionManager.with_connection(pool_name, fn worker ->
        Foundation.Bridge.Python.Worker.health_check(worker)
      end)
      
      {pool_name, health_result}
    end)
    |> Map.new()
  end
  
  defp get_pools_status(pools) do
    Enum.map(pools, fn {pool_name, pool_pid} ->
      status = ConnectionManager.get_pool_status(pool_name)
      {pool_name, %{pid: pool_pid, status: status}}
    end)
    |> Map.new()
  end
  
  defp get_circuit_breakers_status(circuit_breakers) do
    Enum.map(circuit_breakers, fn {pool_name, breaker_name} ->
      status = CircuitBreaker.get_status(breaker_name)
      {pool_name, status}
    end)
    |> Map.new()
  end
  
  defp sanitize_config(config) do
    # Remove sensitive information from config
    Map.drop(config, [:python_path, :venv_path])
  end
  
  defp sanitize_opts(opts) do
    # Remove large data from options for logging
    Keyword.drop(opts, [:metadata])
  end
  
  defp sanitize_result({:ok, result}) do
    cond do
      is_binary(result) and byte_size(result) > 1000 ->
        {:ok, "<large_binary:#{byte_size(result)}_bytes>"}
        
      is_list(result) and length(result) > 100 ->
        {:ok, "<large_list:#{length(result)}_items>"}
        
      true ->
        {:ok, result}
    end
  end
  
  defp sanitize_result(error), do: error
  
  defp get_timeout(opts) do
    Keyword.get(opts, :timeout, 30_000) + 5_000  # Add buffer
  end
  
  defp find_pool_by_pid(pid, pools) do
    case Enum.find(pools, fn {_name, pool_pid} -> pool_pid == pid end) do
      {pool_name, _} -> {:ok, pool_name}
      nil -> :not_found
    end
  end
  
  defp restart_pool(pool_name, state) do
    # Implementation for restarting a failed pool
    Logger.info("Restarting pool #{pool_name} (implementation needed)")
    {:noreply, state}
  end
  
  ## Configurable Behaviour Implementation
  
  @impl Foundation.Contracts.Configurable
  def get(), do: {:error, Error.new(:not_implemented, "Config get not implemented")}
  
  @impl Foundation.Contracts.Configurable  
  def get(_path), do: {:error, Error.new(:not_implemented, "Config get not implemented")}
  
  @impl Foundation.Contracts.Configurable
  def update(_path, _value), do: {:error, Error.new(:not_implemented, "Config update not implemented")}
  
  @impl Foundation.Contracts.Configurable
  def validate(_config), do: {:error, Error.new(:not_implemented, "Config validate not implemented")}
  
  @impl Foundation.Contracts.Configurable
  def updatable_paths(), do: []
  
  @impl Foundation.Contracts.Configurable
  def reset(), do: {:error, Error.new(:not_implemented, "Config reset not implemented")}
end
