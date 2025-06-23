defmodule Foundation.Config.GracefulDegradation do
  @moduledoc """
  Graceful degradation functionality for configuration management.
  Provides fallback mechanisms when the primary config service is unavailable.
  """

  alias Foundation.Config
  alias Foundation.Types.Error
  require Logger

  @fallback_table :config_fallback_cache
  # 5 minutes
  @cache_ttl 300

  @doc """
  Initialize the fallback system with ETS table for caching.
  """
  def initialize_fallback_system do
    case :ets.whereis(@fallback_table) do
      :undefined ->
        :ets.new(@fallback_table, [:named_table, :public, :set, {:read_concurrency, true}])
        Logger.info("Fallback system initialized with ETS table: #{@fallback_table}")
        :ok

      _table ->
        Logger.debug("Fallback system already initialized")
        :ok
    end
  end

  @doc """
  Clean up the fallback system and remove ETS tables.
  """
  def cleanup_fallback_system do
    case :ets.info(@fallback_table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(@fallback_table)
        :ok
    end
  rescue
    ArgumentError ->
      # Table doesn't exist or already deleted
      :ok
  end

  @doc """
  Get configuration value with fallback to cached values.
  """
  # Dialyzer warning suppressed: Config.get/1 success inferred but error handling
  # is required for graceful degradation when service becomes unavailable
  @dialyzer {:nowarn_function, get_with_fallback: 1}
  def get_with_fallback(path) when is_list(path) do
    case Config.get(path) do
      {:ok, value} ->
        # Cache successful result
        cache_key = {:config_cache, path}
        timestamp = System.system_time(:second)
        :ets.insert(@fallback_table, {cache_key, value, timestamp})
        {:ok, value}

      {:error, _reason} ->
        # Try fallback from cache
        get_from_cache(path)
    end
  end

  @doc """
  Update configuration with fallback caching of pending updates.
  """
  # Dialyzer warning suppressed: Config.update/2 success inferred but error handling
  # is essential for pending update caching when service disruptions occur
  @dialyzer {:nowarn_function, update_with_fallback: 2}
  def update_with_fallback(path, value) when is_list(path) do
    case Config.update(path, value) do
      :ok ->
        # Remove any pending update for this path
        pending_key = {:pending_update, path}
        :ets.delete(@fallback_table, pending_key)
        :ok

      {:error, reason} ->
        # Cache as pending update
        timestamp = System.system_time(:second)
        pending_key = {:pending_update, path}
        :ets.insert(@fallback_table, {pending_key, value, timestamp})

        Logger.warning(
          "Config update failed, cached as pending: #{inspect(path)} -> #{inspect(value)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Clean up expired cache entries based on TTL.
  """
  # Dialyzer warning suppressed: ETS operations may not fail in current context,
  # but error patterns ensure robust cleanup in edge cases
  @dialyzer {:nowarn_function, cleanup_expired_cache: 0}
  def cleanup_expired_cache do
    current_time = System.system_time(:second)

    # Get all entries and remove expired ones
    :ets.foldl(
      fn
        {key, _value, timestamp}, _acc when is_integer(timestamp) ->
          if current_time - timestamp > @cache_ttl do
            :ets.delete(@fallback_table, key)
          end

          :ok

        _entry, _acc ->
          :ok
      end,
      :ok,
      @fallback_table
    )

    Logger.debug("Expired cache entries cleaned up")
    :ok
  end

  @doc """
  Retry all pending configuration updates.
  """
  # Dialyzer warning suppressed: Config.update/2 success inferred in retry context,
  # but error handling is necessary for persistent failures and retry logic
  @dialyzer {:nowarn_function, retry_pending_updates: 0}
  def retry_pending_updates do
    # Get all pending updates
    pending_updates =
      :ets.select(@fallback_table, [
        {{{:pending_update, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
      ])

    Logger.debug("Retrying #{length(pending_updates)} pending updates")

    # Try to apply each pending update
    results =
      Enum.map(pending_updates, fn {path, value} ->
        case Config.update(path, value) do
          :ok ->
            # Remove from pending updates
            :ets.delete(@fallback_table, {:pending_update, path})
            Logger.debug("Successfully applied pending update: #{inspect(path)}")
            {:ok, path}

          {:error, reason} ->
            # Keep in pending updates for next retry
            Logger.debug("Pending update still failed: #{inspect(path)} - #{inspect(reason)}")
            {:error, {path, reason}}
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    Logger.info("Retry completed: #{successful}/#{length(pending_updates)} updates successful")

    :ok
  end

  @doc """
  Get current cache statistics.
  """
  def get_cache_stats do
    size = :ets.info(@fallback_table, :size)
    memory = :ets.info(@fallback_table, :memory)

    # Count different types of entries
    config_entries =
      :ets.select_count(@fallback_table, [
        {{{:config_cache, :"$1"}, :"$2", :"$3"}, [], [true]}
      ])

    pending_entries =
      :ets.select_count(@fallback_table, [
        {{{:pending_update, :"$1"}, :"$2", :"$3"}, [], [true]}
      ])

    %{
      total_entries: size,
      memory_words: memory,
      config_cache_entries: config_entries,
      pending_update_entries: pending_entries
    }
  catch
    :error, :badarg ->
      %{error: :table_not_found}
  end

  # Private helper functions

  # Dialyzer warning suppressed: Function may appear unused but is called from
  # get_with_fallback/1 when Config.get/1 fails and cache fallback is needed
  @dialyzer {:nowarn_function, get_from_cache: 1}
  defp get_from_cache(path) do
    cache_key = {:config_cache, path}
    current_time = System.system_time(:second)

    case :ets.lookup(@fallback_table, cache_key) do
      [{^cache_key, value, timestamp}] ->
        if current_time - timestamp <= @cache_ttl do
          Logger.debug("Using cached config value for path: #{inspect(path)}")
          {:ok, value}
        else
          # Cache expired
          :ets.delete(@fallback_table, cache_key)
          Logger.warning("Cache expired for path: #{inspect(path)}")

          {:error,
           Error.new(
             error_type: :config_unavailable,
             message: "Configuration cache expired",
             context: %{path: path},
             category: :config,
             subcategory: :access,
             severity: :medium
           )}
        end

      [] ->
        Logger.warning("No cached value available for path: #{inspect(path)}")

        {:error,
         Error.new(
           error_type: :config_unavailable,
           message: "Configuration not available",
           context: %{path: path},
           category: :config,
           subcategory: :access,
           severity: :medium
         )}
    end
  end
end

defmodule Foundation.Events.GracefulDegradation do
  @moduledoc """
  Graceful degradation for Events service when serialization or storage fails.
  """

  alias Foundation.{Events, Utils}
  alias Foundation.Types.Event
  require Logger

  @doc """
  Create an event safely, handling problematic data.
  """
  def new_event_safe(event_type, data) do
    # Try normal event creation first
    case Events.new_event(event_type, data) do
      {:ok, event} ->
        event

      other ->
        Logger.warning("Unexpected result from Events.new_event: #{inspect(other)}")
        create_minimal_event(event_type, data)
    end
  rescue
    error ->
      Logger.warning("Primary event creation failed: #{Exception.message(error)}")
      # Fallback: create event with sanitized data
      create_fallback_event(event_type, data)
  end

  defp create_fallback_event(event_type, data) do
    sanitized_data = sanitize_data(data)

    case Events.new_event(event_type, sanitized_data) do
      {:ok, event} -> event
      _other -> create_minimal_event(event_type, data)
    end
  rescue
    fallback_error ->
      Logger.error("Fallback event creation also failed: #{Exception.message(fallback_error)}")

      # Last resort: create minimal event
      create_minimal_event(event_type, data)
  end

  @doc """
  Serialize event safely with fallback to JSON.
  """
  def serialize_safe(event) do
    Logger.debug("🚀 GracefulDegradation.serialize_safe called")
    Logger.debug("📥 Input event: #{inspect(event)}")

    # Try normal serialization first
    case Events.serialize(event) do
      {:ok, binary} ->
        Logger.debug("✅ Events.serialize succeeded - binary size: #{byte_size(binary)}")
        Logger.debug("📤 Final serialize_safe result: #{inspect(binary, limit: 50)}")
        binary

      {:error, _reason} ->
        Logger.warning("Events.serialize returned error, using fallback")
        fallback_serialize(event)
    end
  rescue
    error ->
      Logger.warning("Primary serialization failed: #{Exception.message(error)}")
      # Fallback to JSON
      fallback_serialize(event)
  end

  @doc """
  Deserialize event safely with fallback handling.
  """
  def deserialize_safe(binary) when is_binary(binary) do
    # Try normal deserialization first
    Events.deserialize(binary)
  rescue
    error ->
      Logger.warning("Primary deserialization failed: #{Exception.message(error)}")
      # Try JSON fallback
      fallback_deserialize(binary)
  end

  @doc """
  Store event safely with fallback mechanisms.
  """
  def store_safe(event) do
    # Try normal storage first
    Events.store(event)
  rescue
    error ->
      Logger.warning("Primary event storage failed: #{Exception.message(error)}")
      # Fallback: store in memory buffer
      store_in_fallback_buffer(event)
  end

  @doc """
  Query events safely with graceful degradation.
  """
  def query_safe(query_params) do
    # Try normal query first
    Events.query(query_params)
  rescue
    error ->
      Logger.warning("Primary event query failed: #{Exception.message(error)}")
      # Fallback: return empty results with warning
      {:ok, [], %{warning: "Service temporarily unavailable"}}
  end

  # Private helper functions

  defp sanitize_data(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      sanitized_value = sanitize_value(value)
      Map.put(acc, key, sanitized_value)
    end)
  end

  defp sanitize_data(data), do: data

  defp sanitize_value(value) when is_pid(value) do
    inspect(value)
  end

  defp sanitize_value(value) when is_reference(value) do
    inspect(value)
  end

  defp sanitize_value(value) when is_function(value) do
    "#Function<#{inspect(value)}>"
  end

  defp sanitize_value(value) when is_port(value) do
    inspect(value)
  end

  defp sanitize_value(value) when is_map(value) do
    sanitize_data(value)
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value

  defp create_minimal_event(event_type, original_data) do
    %Event{
      event_type: event_type,
      event_id: Utils.generate_id(),
      timestamp: System.system_time(:microsecond),
      wall_time: DateTime.utc_now(),
      node: Node.self(),
      pid: self(),
      correlation_id: nil,
      parent_id: nil,
      data: %{
        original_data_error: "Failed to serialize original data",
        fallback_info: %{
          original_data_type: data_type(original_data),
          sanitization_attempted: true,
          timestamp: DateTime.utc_now()
        }
      }
    }
  end

  defp fallback_serialize(event) do
    # Convert to JSON-safe format
    json_safe_event = make_json_safe(event)
    json_data = Jason.encode!(json_safe_event)
    :erlang.term_to_binary({:json_fallback, json_data})
  rescue
    json_error ->
      Logger.error("JSON fallback serialization failed: #{Exception.message(json_error)}")
      # Absolute fallback: minimal binary representation
      minimal_data = %{
        event_type: event.event_type,
        timestamp: event.timestamp,
        error: "Serialization failed"
      }

      :erlang.term_to_binary({:minimal_fallback, minimal_data})
  end

  defp fallback_deserialize(binary) do
    case :erlang.binary_to_term(binary) do
      {:json_fallback, json_data} ->
        event_data = Jason.decode!(json_data, keys: :atoms)
        {:ok, struct(Event, event_data)}

      {:minimal_fallback, minimal_data} ->
        {:ok, %{fallback_data: minimal_data, warning: "Minimal fallback used"}}

      other ->
        Logger.warning("Unknown fallback format: #{inspect(other)}")
        {:error, :unknown_fallback_format}
    end
  rescue
    error ->
      Logger.error("Fallback deserialization failed: #{Exception.message(error)}")
      {:error, :deserialization_failed}
  end

  defp make_json_safe(%Event{} = event) do
    %{
      event_type: event.event_type,
      event_id: event.event_id,
      timestamp: event.timestamp,
      wall_time: DateTime.to_iso8601(event.wall_time),
      node: to_string(event.node),
      pid: inspect(event.pid),
      correlation_id: event.correlation_id,
      parent_id: event.parent_id,
      data: sanitize_data(event.data)
    }
  end

  defp make_json_safe(data), do: sanitize_data(data)

  defp store_in_fallback_buffer(event) do
    # Store in process dictionary as last resort
    current_buffer = Process.get(:event_fallback_buffer, [])
    # Keep max 100 events
    updated_buffer = [event | Enum.take(current_buffer, 99)]
    Process.put(:event_fallback_buffer, updated_buffer)

    Logger.info("Event stored in fallback buffer (#{length(updated_buffer)} events buffered)")
    :ok
  end

  defp data_type(data) when is_map(data), do: :map
  defp data_type(data) when is_list(data), do: :list
  defp data_type(data) when is_binary(data), do: :binary
  defp data_type(data) when is_atom(data), do: :atom
  defp data_type(data) when is_number(data), do: :number
  defp data_type(data) when is_pid(data), do: :pid
  defp data_type(data) when is_reference(data), do: :reference
  defp data_type(data) when is_function(data), do: :function
  defp data_type(_data), do: :unknown
end
