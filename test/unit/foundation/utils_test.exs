defmodule Foundation.UtilsTest do
  use ExUnit.Case, async: false

  alias Foundation.Utils

  describe "generate_id/0" do
    test "generates unique IDs" do
      id1 = Utils.generate_id()
      id2 = Utils.generate_id()

      assert is_integer(id1)
      assert is_integer(id2)
      assert id1 != id2
    end
  end

  describe "generate_correlation_id/0" do
    test "generates correlation ID with expected format" do
      correlation_id = Utils.generate_correlation_id()

      assert is_binary(correlation_id)
      assert String.length(correlation_id) == 36

      assert String.match?(
               correlation_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
             )
    end

    test "generates unique correlation IDs" do
      id1 = Utils.generate_correlation_id()
      id2 = Utils.generate_correlation_id()

      assert id1 != id2
    end

    test "is available immediately after Foundation startup" do
      # This test reproduces the DSPEx defensive code scenario
      # DSPEx had rescue blocks around generate_correlation_id() calls
      # indicating timing issues during startup

      # Simulate startup scenario by stopping and starting Foundation
      :ok = Application.stop(:foundation)
      {:ok, _} = Application.ensure_all_started(:foundation)

      # Should work immediately without rescue blocks needed
      correlation_id = Utils.generate_correlation_id()

      assert is_binary(correlation_id)
      assert String.length(correlation_id) == 36

      assert String.match?(
               correlation_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
             )
    end
  end

  describe "truncate_if_large/1" do
    test "returns small data unchanged" do
      small_data = [1, 2, 3]

      assert Utils.truncate_if_large(small_data) == small_data
    end

    test "truncates large data" do
      large_data = String.duplicate("x", 20_000)

      result = Utils.truncate_if_large(large_data)

      assert is_map(result)
      assert result.truncated == true
      assert is_integer(result.original_size)
      assert result.original_size > 10_000
    end
  end

  describe "deep_merge/2" do
    test "merges nested maps" do
      map1 = %{a: %{b: 1, c: 2}, d: 3}
      map2 = %{a: %{c: 3, e: 4}, f: 5}

      result = Utils.deep_merge(map1, map2)

      expected = %{a: %{b: 1, c: 3, e: 4}, d: 3, f: 5}
      assert result == expected
    end

    test "overwrites non-map values" do
      map1 = %{a: 1}
      map2 = %{a: 2}

      result = Utils.deep_merge(map1, map2)

      assert result == %{a: 2}
    end
  end

  describe "get_nested/3" do
    test "gets nested value" do
      data = %{a: %{b: %{c: 42}}}

      assert Utils.get_nested(data, [:a, :b, :c]) == 42
    end

    test "returns default for missing path" do
      data = %{a: %{b: 1}}

      assert Utils.get_nested(data, [:a, :x], "default") == "default"
    end

    test "returns default for empty map" do
      assert Utils.get_nested(%{}, [:a], "default") == "default"
    end
  end

  describe "put_nested/3" do
    test "puts nested value" do
      data = %{}

      result = Utils.put_nested(data, [:a, :b, :c], 42)

      assert result == %{a: %{b: %{c: 42}}}
    end

    test "updates existing nested structure" do
      data = %{a: %{b: 1}}

      result = Utils.put_nested(data, [:a, :c], 2)

      assert result == %{a: %{b: 1, c: 2}}
    end
  end

  describe "blank?/1" do
    test "identifies blank values" do
      assert Utils.blank?(nil)
      assert Utils.blank?("")
      assert Utils.blank?("   ")
      assert Utils.blank?([])
      assert Utils.blank?(%{})
    end

    test "identifies non-blank values" do
      refute Utils.blank?("hello")
      refute Utils.blank?([1])
      refute Utils.blank?(%{a: 1})
      refute Utils.blank?(0)
      refute Utils.blank?(false)
    end
  end

  describe "present?/1" do
    test "is opposite of blank?" do
      assert Utils.present?("hello")
      refute Utils.present?(nil)
      refute Utils.present?("")
    end
  end

  describe "retry/2" do
    test "succeeds on first attempt" do
      fun = fn -> {:ok, :success} end

      assert {:ok, :success} = Utils.retry(fun)
    end

    test "retries on failure and eventually succeeds" do
      # Create a function that fails twice then succeeds
      agent = Agent.start_link(fn -> 0 end)
      {:ok, agent_pid} = agent

      fun = fn ->
        count = Agent.get_and_update(agent_pid, fn count -> {count, count + 1} end)
        if count < 2, do: {:error, :failed}, else: {:ok, :success}
      end

      assert {:ok, :success} = Utils.retry(fun, max_attempts: 3, base_delay: 1)

      Agent.stop(agent_pid)
    end

    test "returns error after max attempts" do
      fun = fn -> {:error, :always_fails} end

      assert {:error, :max_attempts_exceeded} = Utils.retry(fun, max_attempts: 2, base_delay: 1)
    end
  end
end

# defmodule Foundation.UtilsTest do
#   use ExUnit.Case, async: false
#   @moduletag :foundation

#   alias Foundation.Utils

#   describe "ID generation" do
#     test "generates unique integer IDs" do
#       id1 = Utils.generate_id()
#       id2 = Utils.generate_id()

#       assert is_integer(id1)
#       assert is_integer(id2)
#       assert id1 != id2
#     end

#     test "generates many unique IDs" do
#       count = 1000
#       ids = for _i <- 1..count, do: Utils.generate_id()

#       unique_ids = Enum.uniq(ids)
#       assert length(unique_ids) == count
#     end

#     test "generates UUID format correlation IDs" do
#       corr_id = Utils.generate_correlation_id()

#       assert is_binary(corr_id)
#       assert String.length(corr_id) == 36

#       assert Regex.match?(
#                ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
#                corr_id
#              )
#     end

#     test "extracts timestamp from ID" do
#       id = Utils.generate_id()
#       extracted_timestamp = Utils.id_to_timestamp(id)

#       assert is_integer(extracted_timestamp)
#     end
#   end

#   describe "time utilities" do
#     test "generates monotonic timestamps" do
#       timestamp1 = Utils.monotonic_timestamp()
#       timestamp2 = Utils.monotonic_timestamp()

#       assert is_integer(timestamp1)
#       assert is_integer(timestamp2)
#       assert timestamp2 >= timestamp1
#     end

#     test "generates wall timestamps" do
#       timestamp = Utils.wall_timestamp()

#       assert is_integer(timestamp)
#       # Should be a reasonable timestamp (after 2020)
#       # 2020-01-01 in nanoseconds
#       assert timestamp > 1_577_836_800_000_000_000
#     end

#     test "formats timestamps correctly" do
#       # 2021-01-01 00:00:00 UTC
#       timestamp_ns = 1_609_459_200_000_000_000
#       formatted = Utils.format_timestamp(timestamp_ns)

#       assert is_binary(formatted)
#       assert String.contains?(formatted, "2021")
#     end
#   end

#   describe "measurement utilities" do
#     test "measures execution time" do
#       # milliseconds
#       sleep_time = 10

#       {result, duration} =
#         Utils.measure(fn ->
#           :timer.sleep(sleep_time)
#           :test_result
#         end)

#       assert result == :test_result
#       assert is_integer(duration)
#       # Convert to nanoseconds
#       assert duration >= sleep_time * 1_000_000
#     end

#     test "measures memory usage" do
#       {result, {mem_before, mem_after, diff}} =
#         Utils.measure_memory(fn ->
#           Enum.to_list(1..1000)
#         end)

#       assert is_list(result)
#       assert length(result) == 1000
#       assert is_integer(mem_before)
#       assert is_integer(mem_after)
#       assert is_integer(diff)
#     end
#   end

#   describe "data utilities" do
#     test "safely inspects terms" do
#       data = %{key: "value", nested: %{list: [1, 2, 3]}}
#       result = Utils.safe_inspect(data)

#       assert is_binary(result)
#       assert String.contains?(result, "key")
#       assert String.contains?(result, "value")
#     end

#     test "truncates large terms" do
#       small_term = "small"
#       large_term = String.duplicate("x", 2000)

#       small_result = Utils.truncate_if_large(small_term, 1000)
#       large_result = Utils.truncate_if_large(large_term, 1000)

#       assert small_result == small_term
#       assert match?({:truncated, _, _}, large_result)
#     end

#     test "estimates term size" do
#       small_term = :atom
#       large_term = String.duplicate("x", 1000)

#       small_size = Utils.term_size(small_term)
#       large_size = Utils.term_size(large_term)

#       assert is_integer(small_size)
#       assert is_integer(large_size)
#       assert large_size > small_size
#     end
#   end

#   describe "formatting utilities" do
#     test "formats bytes correctly" do
#       assert Utils.format_bytes(0) == "0 B"
#       assert Utils.format_bytes(512) == "512 B"
#       assert Utils.format_bytes(1024) == "1.0 KB"
#       assert Utils.format_bytes(1_048_576) == "1.0 MB"
#       assert Utils.format_bytes(1_073_741_824) == "1.0 GB"
#     end

#     test "formats durations correctly" do
#       assert Utils.format_duration(0) == "0 ns"
#       assert Utils.format_duration(500) == "500 ns"
#       assert Utils.format_duration(1_500) == "1.5 μs"
#       assert Utils.format_duration(1_500_000) == "1.5 ms"
#       assert Utils.format_duration(1_500_000_000) == "1.5 s"
#     end
#   end

#   describe "validation utilities" do
#     test "validates positive integers" do
#       assert Utils.valid_positive_integer?(1) == true
#       assert Utils.valid_positive_integer?(100) == true
#       assert Utils.valid_positive_integer?(0) == false
#       assert Utils.valid_positive_integer?(-1) == false
#       assert Utils.valid_positive_integer?(1.5) == false
#       assert Utils.valid_positive_integer?("1") == false
#     end

#     test "validates percentages" do
#       assert Utils.valid_percentage?(0.0) == true
#       assert Utils.valid_percentage?(0.5) == true
#       assert Utils.valid_percentage?(1.0) == true
#       assert Utils.valid_percentage?(-0.1) == false
#       assert Utils.valid_percentage?(1.1) == false
#       assert Utils.valid_percentage?("0.5") == false
#     end

#     test "validates PIDs" do
#       assert Utils.valid_pid?(self()) == true

#       # Create and kill a process
#       dead_pid = spawn(fn -> nil end)
#       Process.sleep(10)
#       assert Utils.valid_pid?(dead_pid) == false

#       assert Utils.valid_pid?("not_a_pid") == false
#     end
#   end

#   describe "system stats" do
#     test "gets process stats for current process" do
#       stats = Utils.process_stats()

#       assert is_map(stats)
#       assert Map.has_key?(stats, :memory)
#       assert Map.has_key?(stats, :reductions)
#       assert Map.has_key?(stats, :message_queue_len)
#       assert Map.has_key?(stats, :timestamp)

#       assert is_integer(stats.memory)
#       assert stats.memory > 0
#     end

#     test "gets system stats" do
#       stats = Utils.system_stats()

#       assert is_map(stats)
#       assert Map.has_key?(stats, :timestamp)
#       assert Map.has_key?(stats, :process_count)
#       assert Map.has_key?(stats, :total_memory)
#       assert Map.has_key?(stats, :scheduler_count)

#       assert is_integer(stats.process_count)
#       assert stats.process_count > 0
#     end
#   end
# end
