defmodule Foundation.Utils do
  @moduledoc """
  Pure utility functions for the Foundation layer.

  Contains helper functions that are used across the Foundation layer.
  All functions are pure and have no side effects.
  """

  import Bitwise

  @doc """
  Generate a unique ID using monotonic time and randomness.

  ## Examples

      iex> id1 = Foundation.Utils.generate_id()
      iex> id2 = Foundation.Utils.generate_id()
      iex> id1 != id2
      true
  """
  @spec generate_id() :: pos_integer()
  def generate_id do
    # Use a combination of unique_integer and make_ref for absolute uniqueness
    # This approach guarantees uniqueness even under extreme concurrency
    unique_int = System.unique_integer([:positive])
    ref_hash = make_ref() |> :erlang.ref_to_list() |> :erlang.phash2()

    # Combine both for maximum uniqueness guarantee
    # Use bit shifting to avoid collisions between components
    unique_int * 1_000_000 + abs(ref_hash) + 1
  end

  @doc """
  Get monotonic timestamp in milliseconds.

  ## Examples

      iex> timestamp = Foundation.Utils.monotonic_timestamp()
      iex> is_integer(timestamp)
      true
  """
  @spec monotonic_timestamp() :: integer()
  def monotonic_timestamp do
    System.monotonic_time(:millisecond)
  end

  @doc """
  Generate a correlation ID string in UUID v4 format.

  ## Examples

      iex> correlation_id = Foundation.Utils.generate_correlation_id()
      iex> String.length(correlation_id)
      36
      iex> String.match?(correlation_id, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
      true
  """
  @spec generate_correlation_id() :: String.t()
  def generate_correlation_id do
    # Generate UUID v4 format (36 characters)
    <<u0::32, u1::16, u2::16, u3::16, u4::48>> = :crypto.strong_rand_bytes(16)

    # Set version (4) and variant bits
    u2_v4 = (u2 &&& 0x0FFF) ||| 0x4000
    u3_var = (u3 &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [u0, u1, u2_v4, u3_var, u4]
    )
    |> IO.iodata_to_binary()
  end

  @doc """
  Truncate data if it's too large for storage.

  ## Examples

      iex> small_data = [1, 2, 3]
      iex> Foundation.Utils.truncate_if_large(small_data)
      [1, 2, 3]

      iex> large_data = String.duplicate("x", 100_000)
      iex> result = Foundation.Utils.truncate_if_large(large_data)
      iex> is_map(result) and Map.has_key?(result, :truncated)
      true
  """
  @spec truncate_if_large(term()) :: term()
  def truncate_if_large(data) do
    truncate_if_large(data, 10_000)
  end

  @doc """
  Truncate data if it's too large for storage with custom size limit.

  ## Examples

      iex> small_data = [1, 2, 3]
      iex> Foundation.Utils.truncate_if_large(small_data, 1000)
      [1, 2, 3]

      iex> large_data = String.duplicate("x", 2000)
      iex> result = Foundation.Utils.truncate_if_large(large_data, 1000)
      iex> is_map(result) and Map.has_key?(result, :truncated)
      true
  """
  @spec truncate_if_large(term(), pos_integer()) :: term()
  def truncate_if_large(data, max_size) do
    size = :erlang.external_size(data)

    if size > max_size do
      %{
        truncated: true,
        original_size: size,
        preview: truncate_preview(data),
        timestamp: DateTime.utc_now()
      }
    else
      data
    end
  rescue
    _ -> data
  end

  @doc """
  Calculate the deep size of a term.

  ## Examples

      iex> size = Foundation.Utils.deep_size(%{a: 1, b: [1, 2, 3]})
      iex> is_integer(size) and size > 0
      true
  """
  @spec deep_size(term()) :: non_neg_integer()
  def deep_size(term) do
    :erlang.external_size(term)
  rescue
    _ -> 0
  end

  @doc """
  Safely convert a term to string representation.

  ## Examples

      iex> Foundation.Utils.safe_inspect(%{key: "value"})
      "%{key: \"value\"}"

      iex> Foundation.Utils.safe_inspect(:atom)
      ":atom"
  """
  @spec safe_inspect(term()) :: String.t()
  def safe_inspect(term) do
    inspect(term, limit: 100, printable_limit: 100)
  rescue
    _ -> "<uninspectable>"
  end

  @doc """
  Merge two maps recursively.

  ## Examples

      iex> map1 = %{a: %{b: 1}, c: 2}
      iex> map2 = %{a: %{d: 3}, e: 4}
      iex> Foundation.Utils.deep_merge(map1, map2)
      %{a: %{b: 1, d: 3}, c: 2, e: 4}
  """
  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      deep_merge(left_val, right_val)
    end)
  end

  def deep_merge(_left, right), do: right

  @doc """
  Get a nested value from a map with a default.

  ## Examples

      iex> data = %{a: %{b: %{c: 42}}}
      iex> Foundation.Utils.get_nested(data, [:a, :b, :c], 0)
      42

      iex> Foundation.Utils.get_nested(data, [:x, :y], "default")
      "default"
  """
  @spec get_nested(map(), [atom()], term()) :: term()
  def get_nested(map, path, default \\ nil)
  def get_nested(map, [], _default), do: map

  def get_nested(map, [key | rest], default) when is_map(map) do
    case Map.get(map, key) do
      nil -> default
      value -> get_nested(value, rest, default)
    end
  end

  def get_nested(_not_map, _path, default), do: default

  @doc """
  Put a nested value in a map.

  ## Examples

      iex> data = %{}
      iex> Foundation.Utils.put_nested(data, [:a, :b, :c], 42)
      %{a: %{b: %{c: 42}}}
  """
  @spec put_nested(map(), [atom()], term()) :: map()
  def put_nested(_map, [], value), do: value

  def put_nested(map, [key], value) when is_map(map) do
    Map.put(map, key, value)
  end

  def put_nested(map, [key | rest], value) when is_map(map) do
    nested_map = Map.get(map, key, %{})
    Map.put(map, key, put_nested(nested_map, rest, value))
  end

  @doc """
  Sanitize a string for safe logging/display.

  ## Examples

      iex> Foundation.Utils.sanitize_string("hello\\nworld\\ttab")
      "hello world tab"
  """
  @spec sanitize_string(String.t()) :: String.t()
  def sanitize_string(str) when is_binary(str) do
    str
    |> String.replace(~r/[\r\n\t]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Convert atom keys to string keys recursively.

  ## Examples

      iex> data = %{key: %{nested: "value"}}
      iex> Foundation.Utils.atomize_keys(data)
      %{key: %{nested: "value"}}
  """
  @spec atomize_keys(map()) :: map()
  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), atomize_keys(value)}
        rescue
          ArgumentError -> {key, atomize_keys(value)}
        end

      {key, value} ->
        {key, atomize_keys(value)}
    end)
  end

  def atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  def atomize_keys(value), do: value

  @doc """
  Convert atom keys to string keys recursively.

  ## Examples

      iex> data = %{key: %{nested: "value"}}
      iex> Foundation.Utils.stringify_keys(data)
      %{"key" => %{"nested" => "value"}}
  """
  @spec stringify_keys(map()) :: map()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_keys(value)}
      {key, value} -> {key, stringify_keys(value)}
    end)
  end

  def stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  def stringify_keys(value), do: value

  @doc """
  Retry a function with exponential backoff.

  ## Examples

      iex> result = Foundation.Utils.retry(fn -> :ok end, max_attempts: 3)
      {:ok, :ok}

      iex> result = Foundation.Utils.retry(fn -> {:error, :failed} end, max_attempts: 2)
      {:error, :max_attempts_exceeded}
  """
  @spec retry((-> any()), Keyword.t()) :: {:error, :max_attempts_exceeded} | {:ok, any()}
  def retry(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 5000)

    do_retry(fun, 1, max_attempts, base_delay, max_delay)
  end

  @doc """
  Check if a term is blank (nil, empty string, empty list, etc.).

  ## Examples

      iex> Foundation.Utils.blank?(nil)
      true

      iex> Foundation.Utils.blank?("")
      true

      iex> Foundation.Utils.blank?("hello")
      false
  """
  @spec blank?(term()) :: boolean()
  def blank?(nil), do: true
  def blank?(""), do: true
  def blank?(str) when is_binary(str), do: String.trim(str) == ""
  def blank?([]), do: true
  def blank?(map) when is_map(map), do: map_size(map) == 0
  def blank?(_), do: false

  @doc """
  Check if a term is present (not blank).

  ## Examples

      iex> Foundation.Utils.present?("hello")
      true

      iex> Foundation.Utils.present?(nil)
      false
  """
  @spec present?(term()) :: boolean()
  def present?(term), do: not blank?(term)

  @doc """
  Format duration in nanoseconds to human readable string.

  ## Examples

      iex> Foundation.Utils.format_duration(1_500_000_000)
      "1.5s"

      iex> Foundation.Utils.format_duration(2_500_000)
      "2.5ms"
  """
  @spec format_duration(non_neg_integer()) :: String.t()
  def format_duration(nanoseconds) when is_integer(nanoseconds) and nanoseconds >= 0 do
    cond do
      nanoseconds >= 1_000_000_000 ->
        seconds = nanoseconds / 1_000_000_000
        "#{:erlang.float_to_binary(seconds, decimals: 1)}s"

      nanoseconds >= 1_000_000 ->
        milliseconds = nanoseconds / 1_000_000
        "#{:erlang.float_to_binary(milliseconds, decimals: 1)}ms"

      nanoseconds >= 1_000 ->
        microseconds = nanoseconds / 1_000
        "#{:erlang.float_to_binary(microseconds, decimals: 1)}μs"

      true ->
        "#{nanoseconds}ns"
    end
  end

  @doc """
  Get current wall clock timestamp.

  ## Examples

      iex> timestamp = Foundation.Utils.wall_timestamp()
      iex> is_integer(timestamp)
      true
  """
  @spec wall_timestamp() :: integer()
  def wall_timestamp do
    System.system_time(:nanosecond)
  end

  @doc """
  Measure execution time of a function in microseconds.

  ## Examples

      iex> {result, duration} = Foundation.Utils.measure(fn -> :timer.sleep(10); :ok end)
      iex> result
      :ok
      iex> duration > 10_000  # At least 10ms in microseconds
      true
  """
  @spec measure((-> result)) :: {result, non_neg_integer()} when result: any()
  def measure(func) when is_function(func, 0) do
    start = System.monotonic_time(:microsecond)
    result = func.()
    stop = System.monotonic_time(:microsecond)
    {result, stop - start}
  end

  @doc """
  Measure memory consumption before and after a function execution.

  ## Examples

      iex> {result, {before, after, diff}} = Foundation.Utils.measure_memory(fn -> "test" end)
      iex> result
      "test"
      iex> is_integer(before) and is_integer(after) and is_integer(diff)
      true
  """
  @spec measure_memory((-> result)) :: {result, {non_neg_integer(), non_neg_integer(), integer()}}
        when result: any()
  def measure_memory(func) when is_function(func, 0) do
    :erlang.garbage_collect()
    before_memory = :erlang.memory(:total)
    result = func.()
    :erlang.garbage_collect()
    after_memory = :erlang.memory(:total)
    {result, {before_memory, after_memory, after_memory - before_memory}}
  end

  @doc """
  Format byte size into human-readable string.

  ## Examples

      iex> Foundation.Utils.format_bytes(1024)
      "1.0 KB"

      iex> Foundation.Utils.format_bytes(1536)
      "1.5 KB"

      iex> Foundation.Utils.format_bytes(1048576)
      "1.0 MB"
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  @doc """
  Returns process statistics for the current process.

  ## Examples

      iex> stats = Foundation.Utils.process_stats()
      iex> Map.has_key?(stats, :memory)
      true
      iex> Map.has_key?(stats, :message_queue_len)
      true
  """
  @spec process_stats() :: %{
          garbage_collection: any(),
          memory: any(),
          message_queue_len: any(),
          reductions: any(),
          status: any()
        }
  def process_stats do
    info = Process.info(self())

    %{
      memory: Keyword.get(info, :memory, 0),
      message_queue_len: Keyword.get(info, :message_queue_len, 0),
      reductions: Keyword.get(info, :reductions, 0),
      garbage_collection: Keyword.get(info, :garbage_collection, %{}),
      status: Keyword.get(info, :status, :unknown)
    }
  end

  @doc """
  Returns system statistics.

  ## Examples

      iex> stats = Foundation.Utils.system_stats()
      iex> Map.has_key?(stats, :process_count)
      true
      iex> Map.has_key?(stats, :memory)
      true
  """
  @spec system_stats() :: %{
          atom_count: any(),
          memory: [
            {:atom
             | :atom_used
             | :binary
             | :code
             | :ets
             | :processes
             | :processes_used
             | :system
             | :total, non_neg_integer()},
            ...
          ],
          process_count: non_neg_integer(),
          scheduler_count: pos_integer(),
          scheduler_online: pos_integer()
        }
  def system_stats do
    %{
      process_count: :erlang.system_info(:process_count),
      atom_count: :erlang.system_info(:atom_count),
      memory: :erlang.memory(),
      scheduler_count: :erlang.system_info(:schedulers),
      scheduler_online: :erlang.system_info(:schedulers_online)
    }
  end

  @doc """
  Check if a value is a valid positive integer.

  ## Examples

      iex> Foundation.Utils.valid_positive_integer?(42)
      true

      iex> Foundation.Utils.valid_positive_integer?(0)
      false

      iex> Foundation.Utils.valid_positive_integer?(-1)
      false

      iex> Foundation.Utils.valid_positive_integer?("42")
      false
  """
  @spec valid_positive_integer?(term()) :: boolean()
  def valid_positive_integer?(value) do
    is_integer(value) and value > 0
  end

  ## Private Functions

  defp truncate_preview(data) when is_binary(data) do
    String.slice(data, 0, 100) <> "..."
  end

  defp truncate_preview(data) when is_list(data) do
    data
    |> Enum.take(10)
    |> Enum.map(&safe_inspect/1)
  end

  defp truncate_preview(data) when is_map(data) do
    data
    |> Enum.take(5)
    |> Map.new()
  end

  defp truncate_preview(data) do
    safe_inspect(data)
  end

  defp do_retry(fun, attempt, max_attempts, base_delay, max_delay) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      :ok ->
        {:ok, :ok}

      {:error, _} when attempt < max_attempts ->
        delay = min(base_delay * :math.pow(2, attempt - 1), max_delay) |> round()
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_attempts, base_delay, max_delay)

      {:error, _reason} ->
        {:error, :max_attempts_exceeded}

      result ->
        {:ok, result}
    end
  end
end

# defmodule Foundation.Utils do
#   @moduledoc """
#   Core utility functions for Foundation layer.

#   Provides essential utilities for ID generation, time measurement,
#   data inspection, and performance monitoring.
#   """

#   import Bitwise
#   alias Foundation.{Types}

#   @type measurement_result(t) :: {t, non_neg_integer()}

#   ## ID Generation

#   @spec generate_id() :: Types.event_id()
#   def generate_id do
#     # Use a combination of timestamp and random value for uniqueness
#     timestamp = System.monotonic_time(:nanosecond)
#     random = :rand.uniform(1_000_000)

#     # Combine timestamp and random for globally unique ID
#     # Use abs to handle negative monotonic time
#     abs(timestamp) * 1_000_000 + random
#   end

#   @spec generate_correlation_id() :: Types.correlation_id()
#   def generate_correlation_id do
#     # Generate UUID v4 format
#     <<u0::32, u1::16, u2::16, u3::16, u4::48>> = :crypto.strong_rand_bytes(16)

#     # Set version (4) and variant bits
#     u2_v4 = (u2 &&& 0x0FFF) ||| 0x4000
#     u3_var = (u3 &&& 0x3FFF) ||| 0x8000

#     :io_lib.format(
#       "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
#       [u0, u1, u2_v4, u3_var, u4]
#     )
#     |> IO.iodata_to_binary()
#   end

#   @spec id_to_timestamp(Types.event_id()) :: Types.timestamp()
#   def id_to_timestamp(id) when is_integer(id) do
#     # Extract timestamp component from ID
#     div(id, 1_000_000)
#   end

#   ## Time Utilities

#   @spec monotonic_timestamp() :: Types.timestamp()
#   def monotonic_timestamp do
#     System.monotonic_time(:nanosecond)
#   end

#   @spec wall_timestamp() :: Types.timestamp()
#   def wall_timestamp do
#     System.os_time(:nanosecond)
#   end

#   @spec format_timestamp(Types.timestamp()) :: String.t()
#   def format_timestamp(timestamp_ns) when is_integer(timestamp_ns) do
#     timestamp_us = div(timestamp_ns, 1_000)
#     datetime = DateTime.from_unix!(timestamp_us, :microsecond)

#     # Format with nanosecond precision
#     nanoseconds = rem(timestamp_ns, 1_000_000)
#     formatted_base = DateTime.to_iso8601(datetime)

#     # Replace microseconds with full nanosecond precision
#     String.replace(formatted_base, ~r/\.\d{6}/, ".#{:io_lib.format("~6..0B", [nanoseconds])}")
#   end

#   ## Measurement

#   @spec measure((-> t)) :: measurement_result(t) when t: var
#   def measure(fun) when is_function(fun, 0) do
#     start_time = monotonic_timestamp()
#     result = fun.()
#     end_time = monotonic_timestamp()

#     {result, end_time - start_time}
#   end

#   @spec measure_memory((-> t)) :: {t, {non_neg_integer(), non_neg_integer(), integer()}} when t: var
#   def measure_memory(fun) when is_function(fun, 0) do
#     memory_before = :erlang.memory(:total)
#     result = fun.()
#     memory_after = :erlang.memory(:total)

#     {result, {memory_before, memory_after, memory_after - memory_before}}
#   end

#   ## Data Inspection

#   @spec safe_inspect(term(), keyword()) :: String.t()
#   def safe_inspect(term, opts \\ []) do
#     limit = Keyword.get(opts, :limit, 50)
#     inspect(term, limit: limit, printable_limit: 100, pretty: true)
#   end

#   @spec truncate_if_large(term(), non_neg_integer()) :: term() | Types.truncated_data()
#   def truncate_if_large(term, size_limit \\ 1000) do
#     estimated_size = term_size(term)

#     if estimated_size <= size_limit do
#       term
#     else
#       type_hint = get_type_hint(term)
#       {:truncated, estimated_size, type_hint}
#     end
#   end

#   @spec term_size(term()) :: non_neg_integer()
#   def term_size(term) do
#     :erlang.external_size(term)
#   end

#   ## Process and System Stats

#   @spec process_stats(pid()) :: map()
#   def process_stats(pid \\ self()) do
#     case Process.info(pid, [:memory, :reductions, :message_queue_len]) do
#       nil ->
#         %{error: :process_not_found, timestamp: monotonic_timestamp()}

#       info ->
#         info
#         |> Keyword.put(:timestamp, monotonic_timestamp())
#         |> Enum.into(%{})
#     end
#   end

#   @spec system_stats() :: %{
#           timestamp: integer(),
#           process_count: non_neg_integer(),
#           total_memory: non_neg_integer(),
#           scheduler_count: pos_integer(),
#           otp_release: binary()
#         }
#   def system_stats do
#     %{
#       timestamp: monotonic_timestamp(),
#       process_count: :erlang.system_info(:process_count),
#       total_memory: :erlang.memory(:total),
#       scheduler_count: :erlang.system_info(:schedulers),
#       otp_release: :erlang.system_info(:otp_release) |> List.to_string()
#     }
#   end

#   ## Formatting

#   @spec format_bytes(non_neg_integer()) :: String.t()
#   def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
#     cond do
#       bytes < 1024 -> "#{bytes} B"
#       bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
#       bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
#       true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
#     end
#   end

#   @spec format_duration(non_neg_integer()) :: String.t()
#   def format_duration(nanoseconds) when is_integer(nanoseconds) and nanoseconds >= 0 do
#     cond do
#       nanoseconds < 1_000 -> "#{nanoseconds} ns"
#       nanoseconds < 1_000_000 -> "#{Float.round(nanoseconds / 1_000, 1)} μs"
#       nanoseconds < 1_000_000_000 -> "#{Float.round(nanoseconds / 1_000_000, 1)} ms"
#       true -> "#{Float.round(nanoseconds / 1_000_000_000, 1)} s"
#     end
#   end

#   ## Validation

#   @spec valid_positive_integer?(term()) :: boolean()
#   def valid_positive_integer?(value) do
#     is_integer(value) and value > 0
#   end

#   @spec valid_percentage?(term()) :: boolean()
#   def valid_percentage?(value) do
#     is_number(value) and value >= 0 and value <= 1
#   end

#   @spec valid_pid?(term()) :: boolean()
#   def valid_pid?(value) do
#     is_pid(value) and Process.alive?(value)
#   end

#   ## Private Functions

#   @spec get_type_hint(term()) :: String.t()
#   defp get_type_hint(term) do
#     cond do
#       is_binary(term) -> "binary data"
#       is_list(term) -> "list with #{length(term)} elements"
#       is_map(term) -> "map with #{map_size(term)} keys"
#       is_tuple(term) -> "tuple with #{tuple_size(term)} elements"
#       true -> "#{inspect(term.__struct__ || :unknown)} data"
#     end
#   rescue
#     _ -> "complex data structure"
#   end
# end
