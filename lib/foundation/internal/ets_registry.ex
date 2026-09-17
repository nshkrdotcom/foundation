defmodule Foundation.Internal.ETSRegistry do
  @moduledoc false

  alias Foundation.Internal.RegistryOwner

  @type registry :: :ets.tid() | atom()

  @spec default_registry(term(), atom(), keyword()) :: registry()
  def default_registry(persistent_key, table_name, opts \\ []) do
    registry = :persistent_term.get(persistent_key, nil)
    owner = Process.whereis(RegistryOwner)

    if is_pid(owner) and valid?(registry) and :ets.info(registry, :owner) == owner do
      registry
    else
      RegistryOwner.fetch(persistent_key, table_name, opts)
    end
  end

  @spec new_registry(atom(), keyword()) :: registry()
  def new_registry(table_name, opts \\ []) do
    case Keyword.get(opts, :name) do
      nil ->
        :ets.new(table_name, table_options())

      name when is_atom(name) ->
        case :ets.whereis(name) do
          :undefined ->
            :ets.new(name, [:named_table | table_options()])

          _tid ->
            name
        end
    end
  end

  @spec resolve_registry(registry(), atom()) :: registry()
  def resolve_registry(registry, table_name) when is_atom(registry) do
    case :ets.whereis(registry) do
      :undefined ->
        _ = new_registry(table_name, name: registry)
        registry

      _tid ->
        registry
    end
  end

  def resolve_registry(registry, _table_name), do: registry

  @spec valid?(registry()) :: boolean()
  def valid?(registry) when is_reference(registry) do
    Enum.member?(:ets.all(), registry)
  end

  def valid?(registry) when is_atom(registry), do: :ets.whereis(registry) != :undefined
  def valid?(_registry), do: false

  defp table_options do
    [
      :set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ]
  end
end
