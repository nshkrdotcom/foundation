defprotocol Foundation.Infrastructure do
  @moduledoc """
  Universal protocol for infrastructure protection patterns.

  ## Protocol Version
  Current version: 1.0

  ## Common Error Returns
  - `{:error, :service_not_found}`
  - `{:error, :circuit_open}`
  - `{:error, :rate_limited}`
  - `{:error, :invalid_config}`
  - `{:error, :timeout}`
  """

  @fallback_to_any true

  # --- Circuit Breaker Pattern ---

  @doc """
  Registers a circuit breaker for a service.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `service_id`: Unique identifier for the service
  - `config`: Circuit breaker configuration map

  ## Configuration Options
  - `:failure_threshold` - Number of failures before opening (default: 5)
  - `:timeout` - Time in ms before attempting to close (default: 60_000)
  - `:success_threshold` - Successes needed to close from half-open (default: 3)

  ## Returns
  - `:ok` on successful registration
  - `{:error, :already_exists}` if service already registered
  - `{:error, :invalid_config}` if configuration is invalid
  """
  @spec register_circuit_breaker(t(), service_id :: term(), config :: map()) ::
          :ok | {:error, term()}
  def register_circuit_breaker(impl, service_id, config)

  @doc """
  Executes a function with circuit breaker protection.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `service_id`: The service identifier
  - `function`: Zero-arity function to execute
  - `context`: Additional context for the execution

  ## Returns
  - `{:ok, result}` if function executes successfully
  - `{:error, :circuit_open}` if circuit is open
  - `{:error, :service_not_found}` if service not registered
  - `{:error, reason}` if function raises or returns error
  """
  @spec execute_protected(t(), service_id :: term(), function :: (-> any()), context :: map()) ::
          {:ok, result :: any()} | {:error, term()}
  def execute_protected(impl, service_id, function, context \\ %{})

  @doc """
  Gets the current status of a circuit breaker.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `service_id`: The service identifier

  ## Returns
  - `{:ok, status}` where status is `:closed`, `:open`, or `:half_open`
  - `{:error, :service_not_found}` if service not registered
  """
  @spec get_circuit_status(t(), service_id :: term()) ::
          {:ok, :closed | :open | :half_open} | {:error, term()}
  def get_circuit_status(impl, service_id)

  # --- Rate Limiting ---

  @doc """
  Sets up a rate limiter for a resource.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `limiter_id`: Unique identifier for the rate limiter
  - `config`: Rate limiter configuration map

  ## Configuration Options
  - `:rate` - Number of requests allowed (required)
  - `:per` - Time period in milliseconds (required)
  - `:burst` - Burst capacity (default: same as rate)
  - `:strategy` - `:token_bucket` or `:sliding_window` (default: `:token_bucket`)

  ## Returns
  - `:ok` on successful setup
  - `{:error, :already_exists}` if limiter already exists
  - `{:error, :invalid_config}` if configuration is invalid
  """
  @spec setup_rate_limiter(t(), limiter_id :: term(), config :: map()) ::
          :ok | {:error, term()}
  def setup_rate_limiter(impl, limiter_id, config)

  @doc """
  Checks if a request is within rate limits.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `limiter_id`: The rate limiter identifier
  - `identifier`: Unique identifier for the requesting entity

  ## Returns
  - `:ok` if request is allowed
  - `{:error, :rate_limited}` if rate limit exceeded
  - `{:error, :limiter_not_found}` if limiter not configured
  """
  @spec check_rate_limit(t(), limiter_id :: term(), identifier :: term()) ::
          :ok | {:error, :rate_limited | :limiter_not_found}
  def check_rate_limit(impl, limiter_id, identifier)

  @doc """
  Gets current rate limit status for an identifier.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `limiter_id`: The rate limiter identifier
  - `identifier`: The entity to check status for

  ## Returns
  - `{:ok, status}` with current usage information
  - `{:error, :limiter_not_found}` if limiter not configured
  """
  @spec get_rate_limit_status(t(), limiter_id :: term(), identifier :: term()) ::
          {:ok, map()} | {:error, term()}
  def get_rate_limit_status(impl, limiter_id, identifier)

  # --- Resource Management ---

  @doc """
  Monitors resource usage for a process or service.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `resource_id`: Unique identifier for the resource
  - `config`: Resource monitoring configuration

  ## Configuration Options
  - `:thresholds` - Map of threshold values (e.g., `%{memory: 0.8, cpu: 0.9}`)
  - `:check_interval` - Monitoring interval in milliseconds (default: 30_000)
  - `:actions` - Actions to take on threshold breach

  ## Returns
  - `:ok` on successful setup
  - `{:error, :invalid_config}` if configuration is invalid
  """
  @spec monitor_resource(t(), resource_id :: term(), config :: map()) ::
          :ok | {:error, term()}
  def monitor_resource(impl, resource_id, config)

  @doc """
  Gets current resource usage statistics.

  ## Parameters
  - `impl`: The infrastructure implementation
  - `resource_id`: The resource identifier

  ## Returns
  - `{:ok, usage_stats}` with current resource usage
  - `{:error, :resource_not_found}` if resource not monitored
  """
  @spec get_resource_usage(t(), resource_id :: term()) ::
          {:ok, map()} | {:error, term()}
  def get_resource_usage(impl, resource_id)

  @doc """
  Returns the protocol version supported by this implementation.

  ## Returns
  - `{:ok, version_string}` - The supported protocol version
  - `{:error, :version_unsupported}` - If version checking is not supported

  ## Examples
      {:ok, "1.0"} = Foundation.Infrastructure.protocol_version(infrastructure_impl)
  """
  @spec protocol_version(t()) :: {:ok, String.t()} | {:error, term()}
  def protocol_version(impl)
end
