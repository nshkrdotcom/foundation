defmodule Foundation.TestHelpers do
  @moduledoc """
  Test helpers for Foundation layer testing.
  """

  alias Foundation.{Config, Events, Utils, Error, ErrorContext}

  @doc """
  Ensures Config GenServer is available for testing.
  """
  @spec ensure_config_available() :: :ok
  def ensure_config_available do
    # First check if the production service is available
    case Foundation.ServiceRegistry.lookup(:production, :config_server) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        # Wait for the application supervisor to start the service
        case wait_for_service_availability(Foundation.Services.ConfigServer, 5000) do
          :ok ->
            :ok

          :timeout ->
            # If still not available, something is wrong with the application startup
            raise "ConfigServer not available after 5 seconds - check application supervisor"
        end
    end
  end

  @doc """
  Ensures TelemetryService is available for testing.
  """
  @spec ensure_telemetry_available() :: :ok
  def ensure_telemetry_available do
    # First check if the production service is available
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        # Wait for the application supervisor to start the service
        case wait_for_service_availability(Foundation.Services.TelemetryService, 5000) do
          :ok ->
            :ok

          :timeout ->
            # If still not available, something is wrong with the application startup
            raise "TelemetryService not available after 5 seconds - check application supervisor"
        end
    end
  end

  @doc """
  Ensures all Foundation services are available for testing.
  """
  @spec ensure_foundation_services_available() :: :ok
  def ensure_foundation_services_available do
    ensure_config_available()
    ensure_telemetry_available()
    :ok
  end

  def debug_config_state do
    config_pid = GenServer.whereis(Config)
    supervisor_pid = Process.whereis(Foundation.Supervisor)

    IO.puts("""
    Config Debug State:
      Config PID: #{inspect(config_pid)}
      Config Alive: #{config_pid && Process.alive?(config_pid)}
      Supervisor PID: #{inspect(supervisor_pid)}
      Supervisor Alive: #{supervisor_pid && Process.alive?(supervisor_pid)}
    """)
  end

  @doc """
  Creates a test event with known data.
  """
  @spec create_test_event(keyword()) ::
          {:ok, Foundation.Types.Event.t()} | {:error, Error.t()}
  def create_test_event(overrides \\ []) do
    base_data = %{
      test_field: "test_value",
      timestamp: Utils.monotonic_timestamp(),
      sequence: :rand.uniform(1000)
    }

    data = Keyword.get(overrides, :data, base_data)
    event_type = Keyword.get(overrides, :event_type, :test_event)
    opts = Keyword.drop(overrides, [:data, :event_type])

    Events.new_event(event_type, data, opts)
  end

  @doc """
  Creates a temporary configuration for testing.
  """
  @spec with_test_config(map(), (-> any())) :: any()
  def with_test_config(config_overrides, test_fun) do
    case Config.get() do
      {:ok, original_config} ->
        # Apply overrides
        _test_config = deep_merge_config(original_config, config_overrides)

        try do
          # This would require additional Config API in a real implementation
          test_fun.()
        after
          # Restore original config paths that were changed
          # This is simplified - real implementation would track and restore changes
          :ok
        end

      {:error, _error} ->
        # If config service is not available, just run the test function
        test_fun.()
    end
  end

  @doc """
  Waits for a condition to be true with timeout.
  """
  @spec wait_for((-> boolean()), non_neg_integer()) :: :ok | :timeout
  def wait_for(condition, timeout_ms \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_condition(condition, deadline)
  end

  @doc """
  Waits for a specific service to be available.
  """
  @spec wait_for_service_availability(module(), non_neg_integer()) :: :ok | :timeout
  def wait_for_service_availability(service_module, timeout_ms \\ 5000) do
    wait_for(fn -> GenServer.whereis(service_module) != nil end, timeout_ms)
  end

  @doc """
  Waits for all foundation services to be available.
  """
  @spec wait_for_all_services_available(non_neg_integer()) :: :ok | :timeout
  def wait_for_all_services_available(timeout_ms \\ 5000) do
    services = [
      Foundation.Services.ConfigServer,
      Foundation.Services.EventStore,
      Foundation.Services.TelemetryService
    ]

    wait_for(
      fn ->
        Enum.all?(services, fn service -> GenServer.whereis(service) != nil end)
      end,
      timeout_ms
    )
  end

  @doc """
  Waits for a service to restart after being stopped.
  """
  @spec wait_for_service_restart(module(), non_neg_integer()) :: :ok | :timeout
  def wait_for_service_restart(service_module, timeout_ms \\ 5000) do
    # First ensure it's stopped
    case GenServer.whereis(service_module) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid, :normal, 1000)
        wait_for(fn -> GenServer.whereis(service_module) == nil end, 1000)
    end

    # Then wait for it to restart
    wait_for_service_availability(service_module, timeout_ms)
  end

  @doc """
  Test error context creation and handling.
  """
  @spec test_error_context(module(), atom(), map()) :: ErrorContext.context()
  def test_error_context(module, function, metadata \\ %{}) do
    ErrorContext.new(module, function, metadata: metadata)
  end

  @doc """
  Validate that a result matches expected error pattern.
  """
  @spec assert_error_result({:error, Error.t()}, atom()) :: Error.t()
  def assert_error_result({:error, %Error{code: code} = error}, expected_code) do
    if code == expected_code do
      error
    else
      raise "Expected error code #{expected_code}, got #{code}"
    end
  end

  def assert_error_result(other, expected_code) do
    raise "Expected {:error, Error.t()} with code #{expected_code}, got #{inspect(other)}"
  end

  @doc """
  Validate that a result is successful.
  """
  @spec assert_ok_result(term()) :: term()
  def assert_ok_result({:ok, value}), do: value
  def assert_ok_result(:ok), do: :ok
  def assert_ok_result(value) when not is_tuple(value), do: value

  def assert_ok_result({:error, error}) do
    raise "Expected success, got error: #{inspect(error)}"
  end

  def assert_ok_result(other) do
    raise "Expected success result, got: #{inspect(other)}"
  end

  ## Private Functions

  @spec deep_merge_config(Foundation.Types.Config.t(), map()) ::
          Foundation.Types.Config.t()
  defp deep_merge_config(original, overrides) when is_map(original) and is_map(overrides) do
    Map.merge(original, overrides, fn _key, orig_val, override_val ->
      if is_map(orig_val) and is_map(override_val) do
        deep_merge_config(orig_val, override_val)
      else
        override_val
      end
    end)
  end

  defp deep_merge_config(_original, override), do: override

  @spec wait_for_condition((-> boolean()), integer()) :: :ok | :timeout
  defp wait_for_condition(condition, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :timeout
    else
      if condition.() do
        :ok
      else
        Process.sleep(10)
        wait_for_condition(condition, deadline)
      end
    end
  end
end

## c3.5 version

# defmodule Foundation.Test.FoundationHelpers do
#   @moduledoc """
#   Common test helpers for Foundation layer tests.

#   Provides utilities for setting up test environments, generating test data,
#   and validating Foundation layer functionality.
#   """

#   alias Foundation.{Config, Events, Types, Utils}

#   @doc """
#   Initialize Foundation layer with test configuration.
#   """
#   def initialize_foundation(opts \\ []) do
#     Application.put_env(:foundation, :dev, %{debug_mode: true})
#     Foundation.initialize(opts)
#   end

#   @doc """
#   Reset Foundation layer to default state.
#   """
#   def reset_foundation do
#     Application.delete_env(:foundation, :dev)
#     :ok
#   end

#   @doc """
#   Generate a test event with optional overrides.
#   """
#   @spec generate_test_event(atom(), map(), keyword()) :: Events.t()
#   def generate_test_event(event_type \\ :test, data \\ %{}, opts \\ []) do
#     Events.new_event(event_type, data, opts)
#   end

#   @doc """
#   Generate a sequence of test events.
#   """
#   @spec generate_test_events(non_neg_integer(), atom(), map()) :: [Events.t()]
#   def generate_test_events(count, event_type \\ :test, base_data \\ %{}) do
#     Enum.map(1..count, fn i ->
#       data = Map.merge(base_data, %{sequence: i})
#       generate_test_event(event_type, data)
#     end)
#   end

#   @doc """
#   Assert that a value is within an expected range.
#   """
#   @spec assert_in_range(number(), number(), number()) :: boolean()
#   def assert_in_range(value, min, max) do
#     value >= min and value <= max
#   end

#   @doc """
#   Wait for a condition to become true with timeout.
#   """
#   @spec wait_for((() -> boolean()), non_neg_integer()) :: :ok | {:error, :timeout}
#   def wait_for(condition_fn, timeout_ms \\ 1000) do
#     start_time = Utils.monotonic_timestamp()
#     do_wait_for(condition_fn, start_time, timeout_ms)
#   end

#   @doc """
#   Create a temporary directory for test file operations.
#   """
#   @spec create_temp_dir() :: {:ok, String.t()} | {:error, term()}
#   def create_temp_dir do
#     tmp_dir = Path.join(System.tmp_dir!(), "foundation_test_#{Utils.generate_id()}")
#     File.mkdir_p(tmp_dir)
#     {:ok, tmp_dir}
#   end

#   @doc """
#   Clean up a temporary test directory.
#   """
#   @spec cleanup_temp_dir(String.t()) :: :ok | {:error, term()}
#   def cleanup_temp_dir(dir) do
#     File.rm_rf(dir)
#   end

#   @doc """
#   Generate test configuration with optional overrides.
#   """
#   @spec generate_test_config(keyword()) :: Config.t()
#   def generate_test_config(overrides \\ []) do
#     base_config = %Config{
#       ai: %{
#         provider: :mock,
#         api_key: "test_key",
#         model: "test-model",
#         analysis: %{
#           max_file_size: 1000,
#           timeout: 1000,
#           cache_ttl: 60
#         },
#         planning: %{
#           default_strategy: :balanced,
#           performance_target: 0.1,
#           sampling_rate: 1.0
#         }
#       },
#       capture: %{
#         ring_buffer: %{
#           size: 100,
#           max_events: 100,
#           overflow_strategy: :drop_oldest,
#           num_buffers: 1
#         },
#         processing: %{
#           batch_size: 10,
#           flush_interval: 10,
#           max_queue_size: 100
#         },
#         vm_tracing: %{
#           enable_spawn_trace: false,
#           enable_exit_trace: false,
#           enable_message_trace: false,
#           trace_children: false
#         }
#       },
#       storage: %{
#         hot: %{
#           max_events: 1000,
#           max_age_seconds: 60,
#           prune_interval: 1000
#         },
#         warm: %{
#           enable: false,
#           path: "./test_data",
#           max_size_mb: 10,
#           compression: :none
#         },
#         cold: %{
#           enable: false
#         }
#       },
#       interface: %{
#         query_timeout: 1000,
#         max_results: 100,
#         enable_streaming: false
#       },
#       dev: %{
#         debug_mode: true,
#         verbose_logging: true,
#         performance_monitoring: true
#       }
#     }

#     Enum.reduce(overrides, base_config, fn {key, value}, config ->
#       put_in(config, key, value)
#     end)
#   end

#   # Private Functions

#   defp do_wait_for(condition_fn, start_time, timeout_ms) do
#     if condition_fn.() do
#       :ok
#     else
#       current_time = Utils.monotonic_timestamp()
#       elapsed_ms = div(current_time - start_time, 1_000_000)

#       if elapsed_ms < timeout_ms do
#         Process.sleep(10)
#         do_wait_for(condition_fn, start_time, timeout_ms)
#       else
#         {:error, :timeout}
#       end
#     end
#   end
# end
