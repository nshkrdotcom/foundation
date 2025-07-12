defmodule ReadWriteBenchmark do
  @moduledoc """
  Benchmark to measure performance of the current read/write pattern in MABEAM.AgentRegistry.
  Tests direct ETS reads vs GenServer calls.
  """

  def run do
    IO.puts("Starting MABEAM.AgentRegistry Read/Write Pattern Benchmark...")
    IO.puts("=" <> String.duplicate("=", 79))

    # Configure Foundation to use MABEAM
    Application.put_env(:foundation, :registry_impl, MABEAM.AgentRegistry)

    # Start the registry
    {:ok, registry} = MABEAM.AgentRegistry.start_link(id: :benchmark)

    # Populate with test data
    IO.puts("\nPopulating registry with test agents...")
    agent_count = 10_000

    for i <- 1..agent_count do
      metadata = %{
        capability: [:inference, :optimization, :coordination] |> Enum.random(),
        health_status: [:healthy, :degraded, :unhealthy] |> Enum.random(),
        node: :"node_#{rem(i, 10)}",
        resources: %{memory_usage: :rand.uniform()}
      }

      :ok = GenServer.call(registry, {:register, "agent_#{i}", self(), metadata})
    end

    IO.puts("Registry populated with #{agent_count} agents")

    # Benchmark configurations
    operations = [
      {"Direct ETS lookup (via protocol)",
       fn ->
         Foundation.Registry.lookup(registry, "agent_#{:rand.uniform(agent_count)}")
       end},
      {"Direct ETS find_by_attribute (via protocol)",
       fn ->
         Foundation.Registry.find_by_attribute(registry, :capability, :inference)
       end},
      {"Direct ETS list_all (via protocol)",
       fn ->
         Foundation.Registry.list_all(registry, nil)
       end},
      {"GenServer query (complex criteria)",
       fn ->
         Foundation.Registry.query(registry, [
           {[:capability], :inference, :eq},
           {[:health_status], :healthy, :eq}
         ])
       end},
      {"Write operation (update_metadata)",
       fn ->
         Foundation.Registry.update_metadata(registry, "agent_#{:rand.uniform(agent_count)}", %{
           capability: [:updated],
           health_status: :healthy,
           node: :updated_node,
           resources: %{memory_usage: 0.5}
         })
       end}
    ]

    # Run benchmarks
    IO.puts("\nRunning benchmarks...")
    IO.puts("-" <> String.duplicate("-", 79))

    results =
      Enum.map(operations, fn {name, operation} ->
        {time, _result} = measure_operation(operation, 1000)
        avg_microseconds = time / 1000
        ops_per_second = 1_000_000 / avg_microseconds

        IO.puts(
          "#{String.pad_trailing(name, 50)} | #{Float.round(avg_microseconds, 2)} μs | #{Float.round(ops_per_second, 0)} ops/s"
        )

        {name, avg_microseconds, ops_per_second}
      end)

    IO.puts("-" <> String.duplicate("-", 79))

    # Summary statistics
    IO.puts("\nSummary:")
    IO.puts("========")

    read_ops = results |> Enum.filter(fn {name, _, _} -> not String.contains?(name, "Write") end)
    write_ops = results |> Enum.filter(fn {name, _, _} -> String.contains?(name, "Write") end)

    avg_read_latency =
      read_ops
      |> Enum.map(fn {_, latency, _} -> latency end)
      |> Enum.sum()
      |> Kernel./(length(read_ops))

    avg_write_latency =
      write_ops
      |> Enum.map(fn {_, latency, _} -> latency end)
      |> Enum.sum()
      |> Kernel./(length(write_ops))

    IO.puts("Average read latency: #{Float.round(avg_read_latency, 2)} μs")
    IO.puts("Average write latency: #{Float.round(avg_write_latency, 2)} μs")
    IO.puts("Read/Write latency ratio: #{Float.round(avg_write_latency / avg_read_latency, 2)}x")

    # Test concurrent reads
    IO.puts("\nConcurrent read test (1000 concurrent operations)...")
    concurrent_test(registry, agent_count)

    # Cleanup
    GenServer.stop(registry)
  end

  defp measure_operation(operation, iterations) do
    # Warmup
    for _ <- 1..100, do: operation.()

    # Measure
    start = System.monotonic_time(:microsecond)
    for _ <- 1..iterations, do: operation.()
    finish = System.monotonic_time(:microsecond)

    {finish - start, iterations}
  end

  defp concurrent_test(registry, agent_count) do
    parent = self()

    start = System.monotonic_time(:microsecond)

    _tasks =
      for _ <- 1..1000 do
        spawn(fn ->
          # Each task does a random lookup
          Foundation.Registry.lookup(registry, "agent_#{:rand.uniform(agent_count)}")
          send(parent, :done)
        end)
      end

    # Wait for all tasks
    for _ <- 1..1000 do
      receive do
        :done -> :ok
      after
        5000 -> raise "Timeout waiting for concurrent operations"
      end
    end

    finish = System.monotonic_time(:microsecond)
    total_time = finish - start
    avg_time = total_time / 1000

    IO.puts("Total time for 1000 concurrent reads: #{Float.round(total_time / 1000, 2)} ms")
    IO.puts("Average time per concurrent read: #{Float.round(avg_time, 2)} μs")
    IO.puts("Theoretical max throughput: #{Float.round(1_000_000 / avg_time * 1000, 0)} ops/s")
  end
end

# Run the benchmark
ReadWriteBenchmark.run()
