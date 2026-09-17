defmodule Foundation.Internal.RegistryOwner do
  @moduledoc false
  use GenServer

  alias Foundation.Internal.ETSRegistry

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def fetch(key, table_name, opts),
    do: GenServer.call(__MODULE__, {:fetch, key, table_name, opts})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:fetch, key, table_name, opts}, _from, tables) do
    registry = Map.get(tables, key)

    registry =
      if ETSRegistry.valid?(registry) do
        registry
      else
        ETSRegistry.new_registry(table_name, opts)
      end

    :persistent_term.put(key, registry)
    {:reply, registry, Map.put(tables, key, registry)}
  end
end
