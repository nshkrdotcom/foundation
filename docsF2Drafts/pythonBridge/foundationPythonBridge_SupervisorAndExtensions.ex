# ==============================================================================
# Python Bridge Supervisor and Extensions
# ==============================================================================

defmodule Foundation.Bridge.Python.Supervisor do
  @moduledoc """
  Supervisor for the Python bridge system.

  Manages the lifecycle of the main bridge process and provides fault tolerance
  with automatic restarts and proper shutdown handling.
  """

  use Supervisor
  require Logger

  @doc """
  Start the Python bridge supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(opts) do
    children = [
      # Main Python bridge process
      {Foundation.Bridge.Python, opts},

      # Optional: Bridge monitor for advanced health checking
      {Foundation.Bridge.Python.Monitor, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# ==============================================================================
# Python Bridge Monitor
# ==============================================================================

defmodule Foundation.Bridge.Python.Monitor do
  @moduledoc """
  Advanced monitoring for Python bridge health and performance.

  Provides periodic health checks, performance monitoring, and automatic
  scaling based on workload patterns.
  """

  use GenServer
  require Logger

  alias Foundation.{Telemetry, Events}
  alias Foundation.Bridge.Python

  @default_config %{
    # Health check interval (ms)
    health_check_interval: 30_000,
    # Performance monitoring interval (ms)
    perf_monitor_interval: 60_000,
    # Auto-scaling config
    auto_scaling: %{
      enabled: false,
      min_pools: 1,
      max_pools: 10,
      scale_up_threshold: 0.8,   # 80% utilization
      scale_down_threshold: 0.3, # 30% utilization
      scale_check_interval: 120_000  # 2 minutes
    }
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %{
      config: config,
      health_timer: nil,
      perf_timer: nil,
      scale_timer: nil,
      metrics_history: []
    }

    schedule_health_check(state)
    schedule_performance_monitoring(state)

    if config.auto_scaling.enabled do
      schedule_scaling_check(state)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    perform_comprehensive_health_check()
    schedule_health_check(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:performance_monitor, state) do
    metrics = collect_performance_metrics()
    new_history = [metrics | Enum.take(state.metrics_history, 59)]  # Keep 1 hour of data

    emit_performance_telemetry(metrics)

    schedule_performance_monitoring(state)
    {:noreply, %{state | metrics_history: new_history}}
  end

  @impl GenServer
  def handle_info(:scaling_check, state) do
    if state.config.auto_scaling.enabled do
      perform_auto_scaling_check(state.metrics_history, state.config.auto_scaling)
    end

    schedule_scaling_check(state)
    {:noreply, state}
  end

  # Private functions

  defp schedule_health_check(state) do
    Process.send_after(self(), :health_check, state.config.health_check_interval)
  end

  defp schedule_performance_monitoring(state) do
    Process.send_after(self(), :performance_monitor, state.config.perf_monitor_interval)
  end

  defp schedule_scaling_check(state) do
    interval = state.config.auto_scaling.scale_check_interval
    Process.send_after(self(), :scaling_check, interval)
  end

  defp perform_comprehensive_health_check() do
    case Python.health_check() do
      {:ok, health_report} ->
        Logger.debug("Python bridge health check: #{inspect(health_report)}")

        # Emit health telemetry
        Telemetry.emit_gauge([:foundation, :python_bridge, :health], 1, %{
          status: health_report.overall_status
        })

      {:error, error} ->
        Logger.warning("Python bridge health check failed: #{inspect(error)}")

        Telemetry.emit_gauge([:foundation, :python_bridge, :health], 0, %{
          error: error.error_type
        })
    end
  end

  defp collect_performance_metrics() do
    case Python.status() do
      {:ok, status} ->
        %{
          timestamp: System.monotonic_time(:millisecond),
          pools: map_size(status.pools),
          metrics: status.metrics,
          uptime_ms: status.uptime_ms
        }

      {:error, _} ->
        %{
          timestamp: System.monotonic_time(:millisecond),
          pools: 0,
          metrics: %{},
          uptime_ms: 0,
          error: true
        }
    end
  end

  defp emit_performance_telemetry(metrics) do
    Telemetry.emit_gauge([:foundation, :python_bridge, :pools], metrics.pools, %{})

    if Map.has_key?(metrics, :metrics) do
      bridge_metrics = metrics.metrics

      Telemetry.emit_gauge([:foundation, :python_bridge, :executions, :successful],
        Map.get(bridge_metrics, :successful_executions, 0), %{})

      Telemetry.emit_gauge([:foundation, :python_bridge, :executions, :failed],
        Map.get(bridge_metrics, :failed_executions, 0), %{})
    end
  end

  defp perform_auto_scaling_check(metrics_history, auto_config) do
    if length(metrics_history) >= 3 do
      recent_metrics = Enum.take(metrics_history, 3)
      avg_utilization = calculate_average_utilization(recent_metrics)

      cond do
        avg_utilization > auto_config.scale_up_threshold ->
          Logger.info("Auto-scaling: High utilization detected (#{avg_utilization}), considering scale up")
          # Implementation would go here

        avg_utilization < auto_config.scale_down_threshold ->
          Logger.info("Auto-scaling: Low utilization detected (#{avg_utilization}), considering scale down")
          # Implementation would go here

        true ->
          :ok
      end
    end
  end

  defp calculate_average_utilization(metrics_list) do
    # Simplified utilization calculation
    # In practice, this would be more sophisticated
    total_executions =
      Enum.map(metrics_list, fn m ->
        metrics = Map.get(m, :metrics, %{})
        Map.get(metrics, :successful_executions, 0) + Map.get(metrics, :failed_executions, 0)
      end)
      |> Enum.sum()

    # Normalize to 0-1 range (assuming max 1000 executions per period indicates full utilization)
    min(total_executions / 1000, 1.0)
  end
end

# ==============================================================================
# Python Bridge Data Serializers
# ==============================================================================

defmodule Foundation.Bridge.Python.Serializers do
  @moduledoc """
  Data serialization utilities for Python bridge communication.

  Provides multiple serialization formats for different use cases:
  - JSON for general purpose data exchange
  - MessagePack for binary data and performance
  - Erlang term format for complex Elixir structures
  """

  alias Foundation.Types.Error

  @type serialization_format :: :json | :msgpack | :erlang_term
  @type serialization_result :: {:ok, binary()} | {:error, Error.t()}
  @type deserialization_result :: {:ok, term()} | {:error, Error.t()}

  @doc """
  Serialize data using the specified format.
  """
  @spec serialize(term(), serialization_format()) :: serialization_result()
  def serialize(data, :json) do
    try do
      encoded = Jason.encode!(data)
      {:ok, encoded}
    rescue
      error ->
        {:error, Error.new(:serialization_failed, "JSON encoding failed: #{inspect(error)}")}
    end
  end

  def serialize(data, :msgpack) do
    try do
      encoded = Msgpax.pack!(data)
      {:ok, encoded}
    rescue
      error ->
        {:error, Error.new(:serialization_failed, "MessagePack encoding failed: #{inspect(error)}")}
    end
  end

  def serialize(data, :erlang_term) do
    try do
      encoded = :erlang.term_to_binary(data)
      {:ok, encoded}
    rescue
      error ->
        {:error, Error.new(:serialization_failed, "Erlang term encoding failed: #{inspect(error)}")}
    end
  end

  @doc """
  Deserialize data using the specified format.
  """
  @spec deserialize(binary(), serialization_format()) :: deserialization_result()
  def deserialize(data, :json) do
    try do
      decoded = Jason.decode!(data)
      {:ok, decoded}
    rescue
      error ->
        {:error, Error.new(:deserialization_failed, "JSON decoding failed: #{inspect(error)}")}
    end
  end

  def deserialize(data, :msgpack) do
    try do
      decoded = Msgpax.unpack!(data)
      {:ok, decoded}
    rescue
      error ->
        {:error, Error.new(:deserialization_failed, "MessagePack decoding failed: #{inspect(error)}")}
    end
  end

  def deserialize(data, :erlang_term) do
    try do
      decoded = :erlang.binary_to_term(data)
      {:ok, decoded}
    rescue
      error ->
        {:error, Error.new(:deserialization_failed, "Erlang term decoding failed: #{inspect(error)}")}
    end
  end

  @doc """
  Convert Elixir data to Python-compatible format.
  """
  @spec to_python_compatible(term()) :: term()
  def to_python_compatible(data) when is_map(data) do
    # Convert maps to ensure string keys for Python compatibility
    data
    |> Enum.map(fn {k, v} -> {to_string(k), to_python_compatible(v)} end)
    |> Map.new()
  end

  def to_python_compatible(data) when is_list(data) do
    Enum.map(data, &to_python_compatible/1)
  end

  def to_python_compatible(data) when is_tuple(data) do
    # Convert tuples to lists for Python compatibility
    data |> Tuple.to_list() |> to_python_compatible()
  end

  def to_python_compatible(data) when is_atom(data) do
    # Convert atoms to strings (except for booleans and nil)
    case data do
      true -> true
      false -> false
      nil -> nil
      atom -> Atom.to_string(atom)
    end
  end

  def to_python_compatible(data), do: data

  @doc """
  Convert Python data to Elixir-compatible format.
  """
  @spec from_python_compatible(term()) :: term()
  def from_python_compatible(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {k, from_python_compatible(v)} end)
    |> Map.new()
  end

  def from_python_compatible(data) when is_list(data) do
    Enum.map(data, &from_python_compatible/1)
  end

  def from_python_compatible(data), do: data
end

# ==============================================================================
# Python Bridge High-Level API
# ==============================================================================

defmodule Foundation.Bridge.Python.API do
  @moduledoc """
  High-level API for common Python operations.

  Provides convenient functions for typical Python integration scenarios
  including data science, machine learning, and general computation tasks.
  """

  alias Foundation.Bridge.Python
  alias Foundation.Bridge.Python.Serializers
  alias Foundation.Types.Error

  @doc """
  Execute a Python script from a file with arguments.

  ## Examples

      {:ok, result} = Python.API.run_script("data_analysis.py",
        args: [dataset_path, output_path],
        timeout: 60_000
      )
  """
  @spec run_script(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def run_script(script_path, opts \\ []) do
    args = Keyword.get(opts, :args, [])
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Convert args to Python sys.argv format
    args_code = """
    import sys
    sys.argv = ['#{script_path}'] + #{Jason.encode!(args)}
    """

    # Read and execute the script
    code = """
    #{args_code}
    exec(open('#{script_path}').read())
    """

    Python.execute(code, timeout: timeout)
  end

  @doc """
  Call a Python function with automatic argument serialization.

  ## Examples

      {:ok, result} = Python.API.call_function("numpy.array", [[1, 2, 3, 4]])
      {:ok, result} = Python.API.call_function("pandas.DataFrame", [data], %{columns: columns})
  """
  @spec call_function(String.t(), list(), map()) :: {:ok, term()} | {:error, Error.t()}
  def call_function(function_name, args \\ [], kwargs \\ %{}) do
    # Build Python function call
    args_json = Jason.encode!(args)
    kwargs_json = Jason.encode!(kwargs)

    code = """
    import json
    args = json.loads('#{String.replace(args_json, "'", "\\'")}')
    kwargs = json.loads('#{String.replace(kwargs_json, "'", "\\'")}')
    result = #{function_name}(*args, **kwargs)
    return result
    """

    Python.execute(code)
  end

  @doc """
  Import a Python module and make it available for subsequent calls.

  ## Examples

      :ok = Python.API.import_module("numpy", as: "np")
      {:ok, result} = Python.API.call_function("np.array", [[1, 2, 3]])
  """
  @spec import_module(String.t(), keyword()) :: :ok | {:error, Error.t()}
  def import_module(module_name, opts \\ []) do
    alias_name = Keyword.get(opts, :as, module_name)

    code = if alias_name == module_name do
      "import #{module_name}"
    else
      "import #{module_name} as #{alias_name}"
    end

    case Python.execute(code) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Execute Python code with automatic data conversion.

  Converts Elixir data structures to Python-compatible formats and back.

  ## Examples

      data = %{numbers: [1, 2, 3], text: "hello"}
      {:ok, result} = Python.API.execute_with_data(
        "result = {'sum': sum(data['numbers']), 'upper': data['text'].upper()}",
        data: data
      )
  """
  @spec execute_with_data(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def execute_with_data(code, opts \\ []) do
    data = Keyword.get(opts, :data, %{})
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Convert data to Python-compatible format
    python_data = Serializers.to_python_compatible(data)
    data_json = Jason.encode!(python_data)

    # Inject data into Python context
    full_code = """
    import json
    data = json.loads('#{String.replace(data_json, "'", "\\'")}')
    #{code}
    """

    case Python.execute(full_code, timeout: timeout) do
      {:ok, result} ->
        # Convert result back to Elixir-compatible format
        elixir_result = Serializers.from_python_compatible(result)
        {:ok, elixir_result}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Execute a data science pipeline with structured input/output.

  ## Examples

      pipeline = \"\"\"
      import pandas as pd
      import numpy as np

      df = pd.DataFrame(input_data)
      df['processed'] = df['value'] * 2
      result = df.to_dict('records')
      return result
      \"\"\"

      {:ok, processed_data} = Python.API.data_pipeline(pipeline,
        input_data: [%{value: 1}, %{value: 2}]
      )
  """
  @spec data_pipeline(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def data_pipeline(pipeline_code, opts \\ []) do
    input_data = Keyword.get(opts, :input_data, [])
    timeout = Keyword.get(opts, :timeout, 60_000)
    pool = Keyword.get(opts, :pool, :data_science)

    # Ensure data science pool exists
    case Python.create_pool(pool,
      size: 3,
      preload_modules: ["pandas", "numpy", "json"]) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, _} = error -> error
    end

    execute_with_data(pipeline_code,
      data: %{input_data: input_data},
      timeout: timeout,
      pool: pool
    )
  end

  @doc """
  Execute machine learning operations with common ML libraries.

  ## Examples

      ml_code = \"\"\"
      from sklearn.linear_model import LinearRegression
      import numpy as np

      X = np.array(training_data['features'])
      y = np.array(training_data['targets'])

      model = LinearRegression()
      model.fit(X, y)

      test_X = np.array(test_data)
      predictions = model.predict(test_X).tolist()

      return {
          'predictions': predictions,
          'score': model.score(X, y)
      }
      \"\"\"

      {:ok, results} = Python.API.ml_execute(ml_code,
        training_data: training_data,
        test_data: test_data
      )
  """
  @spec ml_execute(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def ml_execute(ml_code, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120_000)  # Longer timeout for ML
    pool = Keyword.get(opts, :pool, :machine_learning)

    # Ensure ML pool exists with appropriate modules
    case Python.create_pool(pool,
      size: 2,
      preload_modules: ["numpy", "pandas", "sklearn", "json"]) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, _} = error -> error
    end

    # Extract data variables
    data_vars = Keyword.drop(opts, [:timeout, :pool])

    execute_with_data(ml_code,
      data: Map.new(data_vars),
      timeout: timeout,
      pool: pool
    )
  end

  @doc """
  Execute async Python operations with callback handling.

  ## Examples

      task = Python.API.execute_async("long_computation()",
        callback: fn result ->
          Logger.info("Computation completed: #{inspect(result)}")
        end
      )
  """
  @spec execute_async(String.t(), keyword()) :: Task.t()
  def execute_async(code, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    callback = Keyword.get(opts, :callback)
    pool = Keyword.get(opts, :pool, :async)

    Task.async(fn ->
      result = Python.execute(code, timeout: timeout, pool: pool)

      if callback && is_function(callback, 1) do
        callback.(result)
      end

      result
    end)
  end
end

# ==============================================================================
# Python Bridge Configuration
# ==============================================================================

defmodule Foundation.Bridge.Python.Config do
  @moduledoc """
  Configuration management for Python bridge.

  Provides runtime configuration updates and validation for Python bridge
  settings including pool management, timeouts, and Python environment settings.
  """

  use GenServer
  require Logger

  alias Foundation.{Config}
  alias Foundation.Types.Error

  @config_path [:python_bridge]

  @default_bridge_config %{
    enabled: true,
    python_path: "python3",
    pool_configs: %{
      default: %{size: 5, max_overflow: 10},
      data_science: %{size: 3, max_overflow: 5, preload_modules: ["pandas", "numpy"]},
      machine_learning: %{size: 2, max_overflow: 3, preload_modules: ["sklearn", "tensorflow"]},
      async: %{size: 10, max_overflow: 20}
    },
    timeouts: %{
      default: 30_000,
      data_science: 60_000,
      machine_learning: 120_000
    },
    circuit_breaker: %{
      enabled: true,
      failure_threshold: 5,
      recovery_time: 30_000
    },
    monitoring: %{
      health_check_interval: 30_000,
      performance_monitoring: true,
      auto_scaling: false
    }
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    # Ensure Python bridge config exists in Foundation config
    case Config.get(@config_path) do
      {:ok, _existing_config} ->
        Logger.debug("Python bridge configuration found")

      {:error, _} ->
        Logger.info("Initializing default Python bridge configuration")
        Config.update(@config_path, @default_bridge_config)
    end

    # Subscribe to configuration changes
    Config.subscribe()

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:config_notification, {:config_updated, path, new_value}}, state) do
    if List.starts_with?(path, @config_path) do
      Logger.info("Python bridge configuration updated: #{inspect(path)}")
      handle_config_change(path, new_value)
    end

    {:noreply, state}
  end

  # Public API

  @doc """
  Get current Python bridge configuration.
  """
  @spec get_config() :: {:ok, map()} | {:error, Error.t()}
  def get_config do
    Config.get(@config_path)
  end

  @doc """
  Update Python bridge configuration.
  """
  @spec update_config(map()) :: :ok | {:error, Error.t()}
  def update_config(new_config) when is_map(new_config) do
    case validate_config(new_config) do
      :ok -> Config.update(@config_path, new_config)
      {:error, _} = error -> error
    end
  end

  @doc """
  Get configuration for a specific pool.
  """
  @spec get_pool_config(atom()) :: {:ok, map()} | {:error, Error.t()}
  def get_pool_config(pool_name) do
    case Config.get([@config_path, :pool_configs, pool_name]) do
      {:ok, pool_config} -> {:ok, pool_config}
      {:error, _} -> {:error, Error.new(:pool_config_not_found, "Pool configuration not found")}
    end
  end

  @doc """
  Update configuration for a specific pool.
  """
  @spec update_pool_config(atom(), map()) :: :ok | {:error, Error.t()}
  def update_pool_config(pool_name, pool_config) when is_map(pool_config) do
    Config.update([@config_path, :pool_configs, pool_name], pool_config)
  end

  # Private functions

  defp handle_config_change(path, new_value) do
    case path do
      [@config_path, :pool_configs, pool_name] ->
        # Pool configuration changed - could trigger pool restart
        Logger.info("Pool #{pool_name} configuration updated")

      [@config_path, :timeouts] ->
        # Timeout configuration changed
        Logger.info("Python bridge timeouts updated")

      [@config_path, :circuit_breaker] ->
        # Circuit breaker configuration changed
        Logger.info("Python bridge circuit breaker configuration updated")

      _ ->
        Logger.debug("Other Python bridge configuration updated: #{inspect(path)}")
    end
  end

  defp validate_config(config) when is_map(config) do
    required_keys = [:enabled, :python_path, :pool_configs]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> validate_pool_configs(config.pool_configs)
      false -> {:error, Error.new(:invalid_config, "Missing required configuration keys")}
    end
  end

  defp validate_pool_configs(pool_configs) when is_map(pool_configs) do
    case Enum.all?(pool_configs, fn {_name, config} -> validate_pool_config(config) end) do
      true -> :ok
      false -> {:error, Error.new(:invalid_pool_config, "Invalid pool configuration")}
    end
  end

  defp validate_pool_config(pool_config) when is_map(pool_config) do
    required_keys = [:size, :max_overflow]
    Enum.all?(required_keys, &Map.has_key?(pool_config, &1))
  end

  defp validate_pool_config(_), do: false
end
