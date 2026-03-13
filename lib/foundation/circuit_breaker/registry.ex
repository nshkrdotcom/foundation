defmodule Foundation.CircuitBreaker.Registry do
  @moduledoc """
  ETS-based registry for circuit breaker state.
  """

  alias Foundation.CircuitBreaker
  alias Foundation.Internal.ETSRegistry

  @default_registry_key {__MODULE__, :default_registry}

  @type registry :: :ets.tid() | atom()

  @doc """
  Return the default registry (anonymous ETS table).
  """
  @spec default_registry() :: registry()
  def default_registry do
    ETSRegistry.default_registry(@default_registry_key, __MODULE__)
  end

  @doc """
  Create a new registry. Use `name: :my_table` for a named ETS table.
  """
  @spec new_registry(keyword()) :: registry()
  def new_registry(opts \\ []), do: ETSRegistry.new_registry(__MODULE__, opts)

  @doc """
  Execute a function through a named circuit breaker using the default registry.
  """
  @spec call(String.t(), (-> result), keyword()) :: result | {:error, :circuit_open}
        when result: term()
  def call(name, fun, opts) when is_binary(name) do
    call(default_registry(), name, fun, opts)
  end

  @doc false
  @spec call(registry(), String.t(), (-> result)) :: result | {:error, :circuit_open}
        when result: term()
  def call(registry, name, fun) when is_atom(registry) or is_reference(registry) do
    call(registry, name, fun, [])
  end

  @doc """
  Execute a function through a named circuit breaker using the default registry with default options.
  """
  @spec call(String.t(), (-> result)) :: result | {:error, :circuit_open}
        when result: term()
  def call(name, fun) when is_binary(name) do
    call(default_registry(), name, fun, [])
  end

  @doc """
  Execute a function through a named circuit breaker.
  """
  @spec call(registry(), String.t(), (-> result), keyword()) :: result | {:error, :circuit_open}
        when result: term()
  def call(registry, name, fun, opts) do
    success_fn = Keyword.get(opts, :success?, &default_success?/1)

    case reserve_call(registry, name, opts) do
      {:ok, version, reserved_cb} ->
        execute_reserved_call(registry, name, version, reserved_cb, fun, success_fn, opts)

      {:error, :circuit_open} ->
        {:error, :circuit_open}
    end
  end

  @doc """
  Get the current state of a circuit breaker.
  """
  @spec state(registry(), String.t()) :: CircuitBreaker.state()
  def state(registry, name) do
    case get_cb(registry, name) do
      nil -> :closed
      cb -> CircuitBreaker.state(cb)
    end
  end

  @doc """
  Reset a circuit breaker to closed state.
  """
  @spec reset(registry(), String.t()) :: :ok
  def reset(registry, name) do
    case get_entry(registry, name) do
      nil -> :ok
      {version, cb} -> update_with_retry_raw(registry, name, version, CircuitBreaker.reset(cb))
    end

    :ok
  end

  @doc """
  Delete a circuit breaker from the registry.
  """
  @spec delete(registry(), String.t()) :: :ok
  def delete(registry, name) do
    table = resolve_registry(registry)
    :ets.delete(table, name)
    :ok
  end

  @doc """
  List all circuit breakers and their states.
  """
  @spec list(registry()) :: [{String.t(), CircuitBreaker.state()}]
  def list(registry) do
    table = resolve_registry(registry)

    :ets.tab2list(table)
    |> Enum.map(fn
      {name, cb} -> {name, CircuitBreaker.state(cb)}
      {name, _version, cb} -> {name, CircuitBreaker.state(cb)}
    end)
  end

  defp get_entry(registry, name) do
    table = resolve_registry(registry)

    case :ets.lookup(table, name) do
      [{^name, version, cb}] ->
        {version, cb}

      [{^name, cb}] ->
        :ets.insert(table, {name, 0, cb})
        {0, cb}

      [] ->
        nil
    end
  end

  defp get_cb(registry, name) do
    case get_entry(registry, name) do
      nil -> nil
      {_version, cb} -> cb
    end
  end

  defp get_or_create(registry, name, opts) do
    cb_opts = Keyword.take(opts, [:failure_threshold, :reset_timeout_ms, :half_open_max_calls])

    case get_entry(registry, name) do
      nil ->
        cb = CircuitBreaker.new(name, cb_opts)
        table = resolve_registry(registry)

        case :ets.insert_new(table, {name, 0, cb}) do
          true -> {0, cb}
          false -> get_entry(registry, name)
        end

      {version, cb} ->
        {version, cb}
    end
  end

  defp reserve_call(registry, name, opts) do
    {version, cb} = get_or_create(registry, name, opts)

    case CircuitBreaker.before_call(cb) do
      {:deny, :circuit_open, _cb} ->
        {:error, :circuit_open}

      {:allow, reserved_cb} ->
        if cas_update(registry, name, version, reserved_cb) do
          {:ok, version + 1, reserved_cb}
        else
          reserve_call(registry, name, opts)
        end
    end
  end

  defp execute_reserved_call(registry, name, version, reserved_cb, fun, success_fn, opts) do
    result = fun.()

    persist_result(
      registry,
      name,
      version,
      reserved_cb,
      normalize_outcome(success_fn.(result)),
      opts
    )

    result
  rescue
    exception ->
      persist_result(registry, name, version, reserved_cb, :failure, opts)
      reraise exception, __STACKTRACE__
  end

  defp persist_result(registry, name, version, cb, success?, opts) do
    updated_cb = record_result(cb, success?)

    if cas_update(registry, name, version, updated_cb) do
      :ok
    else
      case get_entry(registry, name) do
        {next_version, cb} ->
          persist_result(registry, name, next_version, cb, success?, opts)

        nil ->
          {next_version, next_cb} = get_or_create(registry, name, opts)
          persist_result(registry, name, next_version, next_cb, success?, opts)
      end
    end
  end

  defp update_with_retry_raw(registry, name, version, updated_cb) do
    if cas_update(registry, name, version, updated_cb) do
      :ok
    else
      case get_entry(registry, name) do
        {next_version, cb} ->
          update_with_retry_raw(registry, name, next_version, CircuitBreaker.reset(cb))

        nil ->
          :ok
      end
    end
  end

  defp cas_update(registry, name, version, cb) do
    table = resolve_registry(registry)
    match_spec = [{{name, version, :"$1"}, [], [{{name, version + 1, cb}}]}]
    :ets.select_replace(table, match_spec) == 1
  end

  defp resolve_registry(registry) when is_atom(registry) do
    ETSRegistry.resolve_registry(registry, __MODULE__)
  end

  defp resolve_registry(registry), do: registry

  defp record_result(cb, :success), do: CircuitBreaker.record_success(cb)
  defp record_result(cb, :failure), do: CircuitBreaker.record_failure(cb)
  defp record_result(cb, :ignore), do: CircuitBreaker.record_ignored(cb)

  defp normalize_outcome(true), do: :success
  defp normalize_outcome(:success), do: :success
  defp normalize_outcome(false), do: :failure
  defp normalize_outcome(:failure), do: :failure
  defp normalize_outcome(:ignore), do: :ignore
  defp normalize_outcome(_other), do: :failure

  defp default_success?({:ok, _}), do: true
  defp default_success?(_), do: false
end
