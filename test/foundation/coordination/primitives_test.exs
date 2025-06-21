# test/foundation/coordination/primitives_test.exs
defmodule Foundation.Coordination.PrimitivesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.Coordination.Primitives
  alias Foundation.{Telemetry}

  setup do
    # Clean up any existing ETS tables
    cleanup_coordination_tables()
    
    # Start telemetry for event verification
    start_supervised!({Foundation.Services.TelemetryService, [namespace: :test]})
    
    :ok
  end

  describe "distributed consensus" do
    test "achieves consensus on simple value with single node" do
      {:committed, value, log_index} = Primitives.consensus(:test_value, nodes: [Node.self()])
      
      assert value == :test_value
      assert is_integer(log_index)
      assert log_index > 0
    end

    test "consensus with custom timeout" do
      start_time = System.monotonic_time(:millisecond)
      result = Primitives.consensus(:test_value, nodes: [Node.self()], timeout: 1000)
      end_time = System.monotonic_time(:millisecond)
      
      assert {:committed, :test_value, _log_index} = result
      assert (end_time - start_time) < 1500  # Should complete well under timeout
    end

    test "consensus with complex data structures" do
      complex_value = %{
        action: :scale_up,
        instances: 3,
        config: %{memory: "2GB", cpu: "1 core"},
        metadata: [timestamp: DateTime.utc_now(), version: "1.0"]
      }
      
      {:committed, result_value, _log_index} = Primitives.consensus(complex_value, nodes: [Node.self()])
      
      assert result_value == complex_value
    end

    test "consensus emits telemetry events" do
      test_pid = self()
      
      # Attach telemetry handlers
      :telemetry.attach("test_consensus_start", [:foundation, :coordination, :consensus, :start], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :start, event, measurements, metadata})
        end, nil)
      
      :telemetry.attach("test_consensus_duration", [:foundation, :coordination, :consensus, :duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :duration, event, measurements, metadata})
        end, nil)
      
      Primitives.consensus(:telemetry_test, nodes: [Node.self()])
      
      # Should receive start event
      assert_receive {:telemetry, :start, [:foundation, :coordination, :consensus, :start], 
        measurements, metadata}, 1000
      
      assert measurements.counter == 1
      assert metadata.node_count == 1
      assert metadata.value_type == :atom
      
      # Should receive duration event
      assert_receive {:telemetry, :duration, [:foundation, :coordination, :consensus, :duration], 
        measurements, metadata}, 1000
      
      assert is_integer(measurements.histogram)
      assert measurements.histogram > 0
      assert metadata.result == :success
      
      :telemetry.detach("test_consensus_start")
      :telemetry.detach("test_consensus_duration")
    end

    test "consensus handles exceptions gracefully" do
      # Test with a function that will cause an error in the consensus process
      # Since we're testing with a single node, we need to simulate an error condition
      result = Primitives.consensus(:test_value, nodes: [Node.self()], timeout: 1)
      
      # With a very short timeout, we might get a timeout or success depending on timing
      assert result in [
        {:committed, :test_value, 1},
        {:timeout, nil},
        {:aborted, :insufficient_acceptances}
      ]
    end

    test "consensus with empty nodes list handles gracefully" do
      result = Primitives.consensus(:test_value, nodes: [])
      
      # Should handle empty nodes list gracefully
      assert {:aborted, :insufficient_acceptances} = result
    end
  end

  describe "leader election" do
    test "elects leader with single node" do
      {:leader_elected, leader_node, term} = Primitives.elect_leader(nodes: [Node.self()])
      
      assert leader_node == Node.self()
      assert is_integer(term)
      assert term > 0
    end

    test "leader election with custom timeout" do
      start_time = System.monotonic_time(:millisecond)
      result = Primitives.elect_leader(nodes: [Node.self()], timeout: 1000)
      end_time = System.monotonic_time(:millisecond)
      
      assert {:leader_elected, Node.self(), _term} = result
      assert (end_time - start_time) < 1500
    end

    test "leader election emits telemetry events" do
      test_pid = self()
      
      :telemetry.attach("test_election_start", [:foundation, :coordination, :election, :start], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :election_start, event, measurements, metadata})
        end, nil)
      
      :telemetry.attach("test_election_duration", [:foundation, :coordination, :election, :duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :election_duration, event, measurements, metadata})
        end, nil)
      
      Primitives.elect_leader(nodes: [Node.self()])
      
      # Should receive start event
      assert_receive {:telemetry, :election_start, [:foundation, :coordination, :election, :start], 
        measurements, metadata}, 1000
      
      assert measurements.counter == 1
      assert metadata.node_count == 1
      
      # Should receive duration event  
      assert_receive {:telemetry, :election_duration, [:foundation, :coordination, :election, :duration], 
        measurements, metadata}, 1000
      
      assert is_integer(measurements.histogram)
      assert metadata.result == :success
      assert metadata.leader == Node.self()
      
      :telemetry.detach("test_election_start")
      :telemetry.detach("test_election_duration")
    end

    test "leader election with very short timeout" do
      result = Primitives.elect_leader(nodes: [Node.self()], timeout: 1)
      
      # Should either succeed quickly or fail with timeout/error
      assert result in [
        {:leader_elected, Node.self(), _term},
        {:election_failed, _reason}
      ] |> case do
        [{:leader_elected, Node.self(), term}] when is_integer(term) -> true
        [{:election_failed, reason}] -> true
        other -> false
      end
    end

    test "leader election handles empty nodes list" do
      result = Primitives.elect_leader(nodes: [])
      
      # Should handle empty nodes gracefully
      case result do
        {:leader_elected, _, _} -> :ok  # Might elect self as leader
        {:election_failed, _} -> :ok   # Or fail appropriately
      end
    end
  end

  describe "distributed mutual exclusion" do
    test "acquires and releases lock successfully" do
      {:acquired, lock_ref} = Primitives.acquire_lock(:test_resource, nodes: [Node.self()])
      
      assert is_reference(lock_ref)
      
      :ok = Primitives.release_lock(lock_ref)
    end

    test "lock acquisition with custom timeout" do
      start_time = System.monotonic_time(:millisecond)
      result = Primitives.acquire_lock(:test_resource, nodes: [Node.self()], timeout: 1000)
      end_time = System.monotonic_time(:millisecond)
      
      assert {:acquired, lock_ref} = result
      assert is_reference(lock_ref)
      assert (end_time - start_time) < 1500
      
      :ok = Primitives.release_lock(lock_ref)
    end

    test "lock operations emit telemetry events" do
      test_pid = self()
      
      :telemetry.attach("test_lock_request", [:foundation, :coordination, :lock, :request], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :lock_request, event, measurements, metadata})
        end, nil)
      
      :telemetry.attach("test_lock_acquired", [:foundation, :coordination, :lock, :acquire_duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :lock_acquired, event, measurements, metadata})
        end, nil)
      
      :telemetry.attach("test_lock_released", [:foundation, :coordination, :lock, :release_duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :lock_released, event, measurements, metadata})
        end, nil)
      
      {:acquired, lock_ref} = Primitives.acquire_lock(:telemetry_resource, nodes: [Node.self()])
      :ok = Primitives.release_lock(lock_ref)
      
      # Should receive request event
      assert_receive {:telemetry, :lock_request, [:foundation, :coordination, :lock, :request], 
        measurements, metadata}, 1000
      
      assert measurements.counter == 1
      assert metadata.resource_id == :telemetry_resource
      assert metadata.node_count == 1
      
      # Should receive acquired event
      assert_receive {:telemetry, :lock_acquired, [:foundation, :coordination, :lock, :acquire_duration], 
        measurements, metadata}, 1000
      
      assert is_integer(measurements.histogram)
      assert metadata.result == :success
      
      # Should receive released event
      assert_receive {:telemetry, :lock_released, [:foundation, :coordination, :lock, :release_duration], 
        measurements, metadata}, 1000
      
      assert is_integer(measurements.histogram)
      assert metadata.result == :success
      
      :telemetry.detach("test_lock_request")
      :telemetry.detach("test_lock_acquired") 
      :telemetry.detach("test_lock_released")
    end

    test "handles lock timeout" do
      result = Primitives.acquire_lock(:timeout_resource, nodes: [Node.self()], timeout: 1)
      
      # With very short timeout, might succeed or timeout
      case result do
        {:acquired, lock_ref} -> 
          :ok = Primitives.release_lock(lock_ref)
        {:timeout, _reason} -> 
          :ok
        {:error, _reason} ->
          :ok
      end
    end

    test "handles invalid lock release" do
      fake_lock_ref = make_ref()
      result = Primitives.release_lock(fake_lock_ref)
      
      # Should handle invalid lock reference gracefully
      assert result in [:ok, {:error, _reason}]
    end

    test "multiple locks on different resources" do
      {:acquired, lock1} = Primitives.acquire_lock(:resource1, nodes: [Node.self()])
      {:acquired, lock2} = Primitives.acquire_lock(:resource2, nodes: [Node.self()])
      
      assert lock1 != lock2
      
      :ok = Primitives.release_lock(lock1)
      :ok = Primitives.release_lock(lock2)
    end
  end

  describe "barrier synchronization" do
    test "single process barrier synchronization" do
      :ok = Primitives.barrier_sync(:test_barrier, 1, 1000)
    end

    test "barrier with multiple processes" do
      barrier_id = :multi_process_barrier
      expected_count = 3
      test_pid = self()
      
      # Spawn processes to reach the barrier
      pids = Enum.map(1..expected_count, fn i ->
        spawn(fn ->
          result = Primitives.barrier_sync(barrier_id, expected_count, 2000)
          send(test_pid, {:barrier_result, i, result})
        end)
      end)
      
      # Wait for all processes to complete
      results = Enum.map(1..expected_count, fn i ->
        receive do
          {:barrier_result, ^i, result} -> result
        after
          3000 -> :timeout
        end
      end)
      
      # All processes should have succeeded
      assert Enum.all?(results, &(&1 == :ok))
      
      # Clean up processes
      Enum.each(pids, fn pid ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)
    end

    test "barrier timeout with insufficient processes" do
      barrier_id = :timeout_barrier
      expected_count = 3
      
      # Only one process reaches the barrier
      result = Primitives.barrier_sync(barrier_id, expected_count, 100)
      
      assert {:timeout, reached_count} = result
      assert is_integer(reached_count)
      assert reached_count < expected_count
    end

    test "barrier emits telemetry events" do
      test_pid = self()
      
      :telemetry.attach("test_barrier_wait", [:foundation, :coordination, :barrier, :wait], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :barrier_wait, event, measurements, metadata})
        end, nil)
      
      :telemetry.attach("test_barrier_complete", [:foundation, :coordination, :barrier, :duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :barrier_complete, event, measurements, metadata})
        end, nil)
      
      :ok = Primitives.barrier_sync(:telemetry_barrier, 1, 1000)
      
      # Should receive wait event
      assert_receive {:telemetry, :barrier_wait, [:foundation, :coordination, :barrier, :wait], 
        measurements, metadata}, 1000
      
      assert measurements.counter == 1
      assert metadata.barrier_id == :telemetry_barrier
      assert metadata.expected_count == 1
      
      # Should receive complete event
      assert_receive {:telemetry, :barrier_complete, [:foundation, :coordination, :barrier, :duration], 
        measurements, metadata}, 1000
      
      assert is_integer(measurements.histogram)
      assert metadata.result == :success
      
      :telemetry.detach("test_barrier_wait")
      :telemetry.detach("test_barrier_complete")
    end
  end

  describe "vector clocks" do
    test "creates and manipulates vector clocks" do
      clock = Primitives.new_vector_clock()
      assert clock == %{}
      
      clock1 = Primitives.increment_clock(clock)
      assert Map.get(clock1, Node.self()) == 1
      
      clock2 = Primitives.increment_clock(clock1)
      assert Map.get(clock2, Node.self()) == 2
    end

    test "increments clock for specific node" do
      clock = Primitives.new_vector_clock()
      node1 = :node1@host
      node2 = :node2@host
      
      clock1 = Primitives.increment_clock(clock, node1)
      clock2 = Primitives.increment_clock(clock1, node2)
      clock3 = Primitives.increment_clock(clock2, node1)
      
      assert Map.get(clock3, node1) == 2
      assert Map.get(clock3, node2) == 1
    end

    test "merges vector clocks correctly" do
      clock1 = %{node1: 2, node2: 1, node3: 0}
      clock2 = %{node1: 1, node2: 3, node4: 2}
      
      merged = Primitives.merge_clocks(clock1, clock2)
      
      assert merged == %{node1: 2, node2: 3, node3: 0, node4: 2}
    end

    test "compares vector clocks for causality" do
      clock1 = %{node1: 1, node2: 1}
      clock2 = %{node1: 2, node2: 1}  # clock2 happened after clock1
      clock3 = %{node1: 1, node2: 2}  # clock3 is concurrent with clock2
      
      assert Primitives.compare_clocks(clock1, clock1) == :equal
      assert Primitives.compare_clocks(clock1, clock2) == :before
      assert Primitives.compare_clocks(clock2, clock1) == :after
      assert Primitives.compare_clocks(clock2, clock3) == :concurrent
      assert Primitives.compare_clocks(clock3, clock2) == :concurrent
    end

    test "handles empty vector clocks" do
      empty1 = Primitives.new_vector_clock()
      empty2 = Primitives.new_vector_clock()
      
      assert Primitives.compare_clocks(empty1, empty2) == :equal
      
      non_empty = Primitives.increment_clock(empty1)
      assert Primitives.compare_clocks(empty2, non_empty) == :before
      assert Primitives.compare_clocks(non_empty, empty2) == :after
    end
  end

  describe "distributed counters" do
    test "increments and reads counters" do
      counter_id = :test_counter
      
      {:ok, value1} = Primitives.increment_counter(counter_id, 1)
      assert value1 == 1
      
      {:ok, value2} = Primitives.increment_counter(counter_id, 5)
      assert value2 == 6
      
      {:ok, current} = Primitives.get_counter(counter_id)
      assert current == 6
    end

    test "handles negative increments" do
      counter_id = :negative_counter
      
      {:ok, value1} = Primitives.increment_counter(counter_id, 10)
      assert value1 == 10
      
      {:ok, value2} = Primitives.increment_counter(counter_id, -3)
      assert value2 == 7
      
      {:ok, current} = Primitives.get_counter(counter_id)
      assert current == 7
    end

    test "multiple counters are independent" do
      {:ok, 1} = Primitives.increment_counter(:counter_a, 1)
      {:ok, 5} = Primitives.increment_counter(:counter_b, 5)
      {:ok, 2} = Primitives.increment_counter(:counter_a, 1)
      
      {:ok, a_value} = Primitives.get_counter(:counter_a)
      {:ok, b_value} = Primitives.get_counter(:counter_b)
      
      assert a_value == 2
      assert b_value == 5
    end

    test "reads non-existent counter as zero" do
      {:ok, value} = Primitives.get_counter(:non_existent_counter)
      assert
