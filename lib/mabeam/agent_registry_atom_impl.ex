defimpl Foundation.Registry, for: Atom do
  @moduledoc """
  Foundation.Registry protocol implementation for Atom (module names).

  This allows using MABEAM.AgentRegistry as a module name in Foundation calls.
  The implementation will call the module's functions directly.
  """

  defp agent_registry?(module_or_name) do
    # Check if it's the MABEAM.AgentRegistry module or a named process
    case module_or_name do
      MABEAM.AgentRegistry ->
        true

      name when is_atom(name) ->
        # Check if it's a registered process that implements AgentRegistry behavior
        case Process.whereis(name) do
          nil ->
            false

          pid when is_pid(pid) ->
            # For test purposes, assume named processes are AgentRegistry instances
            # In production, you might want more sophisticated checking
            true
        end

      _ ->
        false
    end
  end

  def register(module, key, pid, metadata) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          # Use the default named process
          GenServer.call(MABEAM.AgentRegistry, {:register, key, pid, metadata})

        name when is_atom(name) ->
          # Use the named process
          GenServer.call(name, {:register, key, pid, metadata})
      end
    else
      {:error, :unsupported_module}
    end
  end

  def lookup(module, key) do
    if agent_registry?(module) do
      # For named processes, we need to go through GenServer to access the correct ETS tables
      case module do
        MABEAM.AgentRegistry ->
          # Use direct module function for the default registry
          MABEAM.AgentRegistry.lookup(key)

        name when is_atom(name) ->
          # Use GenServer call for named registries to access their specific ETS tables
          try do
            GenServer.call(name, {:lookup, key})
          catch
            :exit, _ -> {:error, :registry_not_available}
          end
      end
    else
      {:error, :unsupported_module}
    end
  end

  def find_by_attribute(module, attribute, value) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          MABEAM.AgentRegistry.find_by_attribute(attribute, value)

        name when is_atom(name) ->
          try do
            GenServer.call(name, {:find_by_attribute, attribute, value})
          catch
            :exit, _ -> {:error, :registry_not_available}
          end
      end
    else
      {:error, :unsupported_module}
    end
  end

  def query(module, criteria) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          MABEAM.AgentRegistry.query(criteria)

        name when is_atom(name) ->
          try do
            GenServer.call(name, {:query, criteria})
          catch
            :exit, _ -> {:error, :registry_not_available}
          end
      end
    else
      {:error, :unsupported_module}
    end
  end

  def indexed_attributes(module) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          MABEAM.AgentRegistry.indexed_attributes()

        name when is_atom(name) ->
          try do
            GenServer.call(name, {:indexed_attributes})
          catch
            :exit, _ -> []
          end
      end
    else
      []
    end
  end

  def list_all(module, filter) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          MABEAM.AgentRegistry.list_all(filter)

        name when is_atom(name) ->
          try do
            GenServer.call(name, {:list_all, filter})
          catch
            :exit, _ -> []
          end
      end
    else
      []
    end
  end

  def update_metadata(module, key, metadata) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          # Use the default named process
          GenServer.call(MABEAM.AgentRegistry, {:update_metadata, key, metadata})

        name when is_atom(name) ->
          # Use the named process
          GenServer.call(name, {:update_metadata, key, metadata})
      end
    else
      {:error, :unsupported_module}
    end
  end

  def unregister(module, key) do
    if agent_registry?(module) do
      case module do
        MABEAM.AgentRegistry ->
          # Use the default named process
          GenServer.call(MABEAM.AgentRegistry, {:unregister, key})

        name when is_atom(name) ->
          # Use the named process
          GenServer.call(name, {:unregister, key})
      end
    else
      {:error, :unsupported_module}
    end
  end
end
