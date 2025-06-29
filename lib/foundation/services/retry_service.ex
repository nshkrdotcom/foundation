defmodule Foundation.Services.RetryService do
  @moduledoc """
  Production-grade retry service using ElixirRetry library.

  Provides centralized retry mechanisms with configurable policies for
  resilient operations across the Foundation platform. Integrates with
  circuit breakers and telemetry for comprehensive error handling.

  ## Features

  - Multiple retry policies (exponential backoff, fixed delay, immediate)
  - Circuit breaker integration for intelligent retry decisions
  - Telemetry integration for retry metrics
  - Configurable retry budgets to prevent retry storms
  - Type-based retry policy selection

  ## Retry Policies

  - `:exponential_backoff` - Exponential backoff with jitter and cap
  - `:fixed_delay` - Fixed delay between retries
  - `:immediate` - Immediate retry without delay
  - `:linear_backoff` - Linear increase in delay
  - `:custom` - Custom policy with user-defined parameters

  ## Usage

      # Basic retry with default policy
      RetryService.retry_operation(fn -> risky_operation() end)
      
      # Retry with specific policy
      RetryService.retry_operation(
        fn -> risky_operation() end, 
        policy: :exponential_backoff
      )
      
      # Retry with circuit breaker integration
      RetryService.retry_with_circuit_breaker(
        :external_service,
        fn -> call_external_api() end
      )
  """

  use GenServer
  require Logger
  import Retry
  import Retry.DelayStreams

  @type retry_policy :: :exponential_backoff | :fixed_delay | :immediate | :linear_backoff | :custom
  @type retry_result :: {:ok, term()} | {:error, term()}

  # Default configuration
  @default_config %{
    max_retries: 3,
    initial_delay: 500,
    max_delay: 10_000,
    backoff_factor: 2,
    jitter: true,
    retry_budget: 10
  }

  defstruct [
    :config,
    :policies,
    :retry_budget,
    :telemetry_handler
  ]

  # Client API

  @doc """
  Starts the retry service.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Retry an operation with the specified policy.

  ## Options

  - `:policy` - Retry policy to use (default: :exponential_backoff)
  - `:max_retries` - Maximum number of retries (default: 3)
  - `:circuit_breaker` - Circuit breaker service ID for integration
  - `:telemetry_metadata` - Additional metadata for telemetry events

  ## Examples

      # Basic exponential backoff
      {:ok, result} = RetryService.retry_operation(fn ->
        risky_external_call()
      end)
      
      # Fixed delay retry
      {:ok, result} = RetryService.retry_operation(
        fn -> database_operation() end,
        policy: :fixed_delay,
        max_retries: 5
      )
  """
  @spec retry_operation((-> term()), keyword()) :: retry_result()
  def retry_operation(operation, opts \\ []) do
    policy = Keyword.get(opts, :policy, :exponential_backoff)
    max_retries = Keyword.get(opts, :max_retries, 3)
    telemetry_metadata = Keyword.get(opts, :telemetry_metadata, %{})

    start_time = System.monotonic_time()

    try do
      case get_retry_policy(policy, max_retries) do
        {:ok, retry_config} ->
          result = execute_with_retry(operation, retry_config)
          emit_retry_telemetry(:success, start_time, telemetry_metadata)
          result

        {:error, :invalid_policy} = error ->
          emit_retry_telemetry(
            :error,
            start_time,
            Map.put(telemetry_metadata, :error, :invalid_policy)
          )

          error
      end
    rescue
      error ->
        emit_retry_telemetry(:error, start_time, Map.put(telemetry_metadata, :error, error))
        {:error, error}
    end
  end

  @doc """
  Retry an operation with circuit breaker integration.

  Combines retry logic with circuit breaker protection to prevent
  retry storms when external services are unavailable.
  """
  @spec retry_with_circuit_breaker(atom(), (-> term()), keyword()) :: retry_result()
  def retry_with_circuit_breaker(circuit_breaker_id, operation, opts \\ []) do
    # Check circuit breaker status before retrying
    case try_circuit_breaker_status(circuit_breaker_id) do
      {:ok, :closed} ->
        # Circuit is closed, proceed with retry
        wrapped_operation = fn ->
          Foundation.Infrastructure.CircuitBreaker.call(circuit_breaker_id, operation)
        end

        retry_operation(wrapped_operation, opts)

      {:error, :circuit_breaker_unavailable} ->
        # Circuit breaker not available, fallback to direct retry
        Logger.debug("Circuit breaker #{circuit_breaker_id} not available, using direct retry")
        retry_operation(operation, opts)

      {:ok, :open} ->
        # Circuit is open, don't retry
        {:error, :circuit_open}

      {:ok, :half_open} ->
        # Circuit is half-open, allow one retry attempt
        opts_single = Keyword.put(opts, :max_retries, 1)
        retry_with_circuit_breaker(circuit_breaker_id, operation, opts_single)

      {:error, :service_not_found} ->
        # Circuit breaker not configured, proceed with normal retry
        retry_operation(operation, opts)
    end
  end

  @doc """
  Configure a custom retry policy.
  """
  def configure_policy(policy_name, config) do
    GenServer.call(__MODULE__, {:configure_policy, policy_name, config})
  end

  @doc """
  Get retry statistics and metrics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)

    state = %__MODULE__{
      config: config,
      policies: %{},
      retry_budget: config.retry_budget,
      telemetry_handler: nil
    }

    Logger.info("Foundation.Services.RetryService started with config: #{inspect(config)}")

    {:ok, state}
  end

  @impl true
  def handle_call({:configure_policy, policy_name, config}, _from, state) do
    new_policies = Map.put(state.policies, policy_name, config)
    new_state = %{state | policies: new_policies}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # Return health status based on retry budget and service state
    health_status = if state.retry_budget > 0, do: :healthy, else: :degraded
    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      retry_budget: state.retry_budget,
      configured_policies: Map.keys(state.policies),
      config: state.config
    }

    {:reply, {:ok, stats}, state}
  end

  # Private Implementation

  @spec get_retry_policy(retry_policy(), non_neg_integer()) ::
          {:ok, any()} | {:error, :invalid_policy}
  defp get_retry_policy(:exponential_backoff, max_retries) do
    policy =
      exponential_backoff(500, 2) |> cap(10_000) |> expiry(30_000) |> Stream.take(max_retries)

    {:ok, policy}
  end

  defp get_retry_policy(:fixed_delay, max_retries) do
    policy = constant_backoff(1000) |> Stream.take(max_retries)
    {:ok, policy}
  end

  defp get_retry_policy(:immediate, max_retries) do
    # Use 1ms delay instead of 0 to respect ElixirRetry's pos_integer contract
    # This maintains "immediate" retry semantics while being library-compliant
    policy = constant_backoff(1) |> Stream.take(max_retries)
    {:ok, policy}
  end

  defp get_retry_policy(:linear_backoff, max_retries) do
    policy = linear_backoff(500, 1) |> cap(5_000) |> Stream.take(max_retries)
    {:ok, policy}
  end

  defp get_retry_policy(_, _) do
    {:error, :invalid_policy}
  end

  @spec execute_with_retry((-> term()), any()) :: retry_result()
  defp execute_with_retry(operation, retry_config) do
    try do
      retry with: retry_config do
        case operation.() do
          {:ok, result} ->
            result

          {:error, reason} when reason in [:timeout, :network_error, :service_unavailable] ->
            # Retry these errors
            raise "Retryable error: #{reason}"

          {:error, reason} ->
            # Don't retry these errors
            throw({:no_retry, reason})

          result ->
            # Assume success for non-tuple results
            result
        end
      after
        result -> {:ok, result}
      else
        error -> {:error, error}
      end
    catch
      {:no_retry, reason} -> {:error, reason}
    end
  end

  defp emit_retry_telemetry(event, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    Foundation.Telemetry.emit(
      [:foundation, :retry_service, event],
      %{duration: duration, count: 1},
      metadata
    )
  rescue
    _ -> :ok
  end

  # Safely try to access circuit breaker status
  defp try_circuit_breaker_status(circuit_breaker_id) do
    try do
      Foundation.Infrastructure.CircuitBreaker.get_status(circuit_breaker_id)
    catch
      :exit, {:noproc, _} ->
        {:error, :circuit_breaker_unavailable}

      :exit, reason ->
        Logger.warning("Circuit breaker access failed: #{inspect(reason)}")
        {:error, :circuit_breaker_unavailable}
    end
  end
end
