defmodule Foundation.CircuitBreaker.Registry do
  @moduledoc """
  ETS-based registry for circuit breaker state.
  """

  alias Foundation.CircuitBreaker

  @default_registry_key {__MODULE__, :default_registry}

  @type registry :: :ets.tid() | atom()

  @doc """
  Return the default registry (anonymous ETS table).
  """
  @spec default_registry() :: registry()
  def default_registry do
    case :persistent_term.get(@default_registry_key, nil) do
      nil ->
        table = new_registry()
        :persistent_term.put(@default_registry_key, table)
        table

      table ->
        table
    end
  end

  @doc """
  Create a new registry. Use `name: :my_table` for a named ETS table.
  """
  @spec new_registry(keyword()) :: registry()
  def new_registry(opts \\ []) do
    case Keyword.get(opts, :name) do
      nil ->
        :ets.new(__MODULE__, [
          :set,
          :public,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      name when is_atom(name) ->
        case :ets.whereis(name) do
          :undefined ->
            :ets.new(name, [
              :set,
              :public,
              :named_table,
              {:read_concurrency, true},
              {:write_concurrency, true}
            ])

          _tid ->
            name
        end
    end
  end

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
    {version, cb} = get_or_create(registry, name, opts)
    success_fn = Keyword.get(opts, :success?, &default_success?/1)
    current_state = CircuitBreaker.state(cb)

    if allow_request?(cb, current_state) do
      result = fun.()
      success? = success_fn.(result)
      updated_cb = apply_result(cb, success?)
      update_with_retry(registry, name, version, updated_cb, success?, opts)
      result
    else
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

  defp allow_request?(cb, current_state) do
    case current_state do
      :closed -> true
      :open -> false
      :half_open -> cb.half_open_calls < cb.half_open_max_calls
    end
  end

  defp apply_result(cb, success?) do
    current_state = CircuitBreaker.state(cb)

    cb =
      if current_state == :half_open do
        %{cb | half_open_calls: cb.half_open_calls + 1}
      else
        cb
      end

    if success? do
      CircuitBreaker.record_success(cb)
    else
      CircuitBreaker.record_failure(cb)
    end
  end

  defp update_with_retry(registry, name, version, updated_cb, success?, opts) do
    if cas_update(registry, name, version, updated_cb) do
      :ok
    else
      case get_entry(registry, name) do
        {next_version, cb} ->
          next_cb = apply_result(cb, success?)
          update_with_retry(registry, name, next_version, next_cb, success?, opts)

        nil ->
          {next_version, cb} = get_or_create(registry, name, opts)
          next_cb = apply_result(cb, success?)
          update_with_retry(registry, name, next_version, next_cb, success?, opts)
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

  defp default_success?({:ok, _}), do: true
  defp default_success?(_), do: false

  defp resolve_registry(registry) when is_atom(registry) do
    case :ets.whereis(registry) do
      :undefined ->
        _ = new_registry(name: registry)
        registry

      _tid ->
        registry
    end
  end

  defp resolve_registry(registry), do: registry
end
