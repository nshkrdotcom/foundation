defmodule MABEAM.ProcessRegistry.Backend.LocalETSTest do
  use ExUnit.Case, async: false

  alias MABEAM.ProcessRegistry.Backend.LocalETS
  alias MABEAM.Types

  setup do
    # Each test gets its own ETS table
    table_name = :"test_registry_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = LocalETS.init(table_name: table_name)

    %{table_name: table_name}
  end

  describe "ETS backend operations" do
    test "basic CRUD operations", %{table_name: _table} do
      config = Types.new_agent_config(:test_agent, GenServer, [])

      entry = %{
        id: config.id,
        config: config,
        pid: nil,
        status: :registered,
        started_at: nil,
        stopped_at: nil,
        metadata: config.metadata,
        node: node()
      }

      # Create
      assert :ok = LocalETS.register_agent(entry)

      # Read
      assert {:ok, retrieved} = LocalETS.get_agent(:test_agent)
      assert retrieved.id == entry.id
      assert retrieved.config == entry.config
      assert retrieved.status == :registered

      # Update
      assert :ok = LocalETS.update_agent_status(:test_agent, :running, self())

      assert {:ok, updated_retrieved} = LocalETS.get_agent(:test_agent)
      assert updated_retrieved.status == :running
      assert updated_retrieved.pid == self()

      # Delete
      assert :ok = LocalETS.unregister_agent(:test_agent)
      assert {:error, :not_found} = LocalETS.get_agent(:test_agent)
    end

    test "handles duplicate registration attempts", %{table_name: _table} do
      config = Types.new_agent_config(:duplicate_test, GenServer, [])

      entry = %{
        id: config.id,
        config: config,
        pid: nil,
        status: :registered,
        started_at: nil,
        stopped_at: nil,
        metadata: %{},
        node: node()
      }

      assert :ok = LocalETS.register_agent(entry)
      assert {:error, :already_registered} = LocalETS.register_agent(entry)
    end

    test "concurrent access safety", %{table_name: _table} do
      # Test concurrent writes
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            config = Types.new_agent_config(:"agent_#{i}", GenServer, [])

            entry = %{
              id: config.id,
              config: config,
              pid: nil,
              status: :registered,
              started_at: nil,
              stopped_at: nil,
              metadata: %{},
              node: node()
            }

            LocalETS.register_agent(entry)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all entries exist
      all_entries = LocalETS.list_all_agents()
      assert length(all_entries) == 50
    end

    test "memory usage with large datasets", %{table_name: _table} do
      # Insert many entries
      for i <- 1..1000 do
        config =
          Types.new_agent_config(:"large_#{i}", GenServer, [],
            metadata: %{
              index: i,
              # Some bulk data
              data: String.duplicate("x", 100)
            }
          )

        entry = %{
          id: config.id,
          config: config,
          pid: nil,
          status: :registered,
          started_at: nil,
          stopped_at: nil,
          metadata: config.metadata,
          node: node()
        }

        assert :ok = LocalETS.register_agent(entry)
      end

      # Verify all entries exist
      all_entries = LocalETS.list_all_agents()
      assert length(all_entries) == 1000

      # Test lookup performance
      {time_micro, {:ok, _entry}} =
        :timer.tc(fn ->
          LocalETS.get_agent(:large_500)
        end)

      # Lookup should be very fast (< 1ms)
      assert time_micro < 1000
    end

    test "capability-based search", %{table_name: _table} do
      # Register agents with different capabilities
      configs = [
        Types.new_agent_config(:worker1, GenServer, [], capabilities: [:task_execution]),
        Types.new_agent_config(:worker2, GenServer, [], capabilities: [:data_processing]),
        Types.new_agent_config(:ml_agent, GenServer, [], capabilities: [:nlp, :classification]),
        Types.new_agent_config(:hybrid, GenServer, [], capabilities: [:task_execution, :nlp])
      ]

      for config <- configs do
        entry = %{
          id: config.id,
          config: config,
          pid: nil,
          status: :registered,
          started_at: nil,
          stopped_at: nil,
          metadata: %{},
          node: node()
        }

        assert :ok = LocalETS.register_agent(entry)
      end

      # Test capability searches
      {:ok, task_agents} = LocalETS.find_agents_by_capability([:task_execution])
      assert :worker1 in task_agents
      assert :hybrid in task_agents
      assert length(task_agents) == 2

      {:ok, nlp_agents} = LocalETS.find_agents_by_capability([:nlp])
      assert :ml_agent in nlp_agents
      assert :hybrid in nlp_agents
      assert length(nlp_agents) == 2

      {:ok, multi_cap_agents} = LocalETS.find_agents_by_capability([:task_execution, :nlp])
      assert :hybrid in multi_cap_agents
      assert length(multi_cap_agents) == 1
    end

    test "status-based queries", %{table_name: _table} do
      # Register agents with different statuses
      configs = [
        {:running_agent, :running},
        {:stopped_agent, :stopped},
        {:failed_agent, :failed},
        {:starting_agent, :starting}
      ]

      for {agent_id, status} <- configs do
        config = Types.new_agent_config(agent_id, GenServer, [])

        entry = %{
          id: config.id,
          config: config,
          pid: if(status == :running, do: self(), else: nil),
          status: status,
          started_at: if(status in [:running, :stopped], do: DateTime.utc_now(), else: nil),
          stopped_at: if(status == :stopped, do: DateTime.utc_now(), else: nil),
          metadata: %{},
          node: node()
        }

        assert :ok = LocalETS.register_agent(entry)
      end

      # Test status queries
      {:ok, running} = LocalETS.get_agents_by_status(:running)
      assert length(running) == 1
      assert hd(running).id == :running_agent

      {:ok, stopped} = LocalETS.get_agents_by_status(:stopped)
      assert length(stopped) == 1
      assert hd(stopped).id == :stopped_agent

      {:ok, failed} = LocalETS.get_agents_by_status(:failed)
      assert length(failed) == 1
      assert hd(failed).id == :failed_agent
    end

    test "cleanup inactive agents", %{table_name: _table} do
      # Register agents with various statuses
      active_config = Types.new_agent_config(:active_agent, GenServer, [])
      stopped_config = Types.new_agent_config(:stopped_agent, GenServer, [])
      failed_config = Types.new_agent_config(:failed_agent, GenServer, [])

      entries = [
        %{
          id: :active_agent,
          config: active_config,
          pid: self(),
          status: :running,
          started_at: DateTime.utc_now(),
          stopped_at: nil,
          metadata: %{},
          node: node()
        },
        %{
          id: :stopped_agent,
          config: stopped_config,
          pid: nil,
          status: :stopped,
          started_at: DateTime.utc_now(),
          stopped_at: DateTime.utc_now(),
          metadata: %{},
          node: node()
        },
        %{
          id: :failed_agent,
          config: failed_config,
          pid: nil,
          status: :failed,
          started_at: DateTime.utc_now(),
          stopped_at: DateTime.utc_now(),
          metadata: %{},
          node: node()
        }
      ]

      for entry <- entries do
        assert :ok = LocalETS.register_agent(entry)
      end

      # Cleanup should remove inactive agents
      {:ok, cleaned_count} = LocalETS.cleanup_inactive_agents()
      # stopped and failed agents
      assert cleaned_count == 2

      # Verify only active agent remains
      all_agents = LocalETS.list_all_agents()
      assert length(all_agents) == 1
      assert hd(all_agents).id == :active_agent
    end

    test "performance benchmarks", %{table_name: _table} do
      # Register many agents for performance testing
      agent_count = 1000

      for i <- 1..agent_count do
        config =
          Types.new_agent_config(:"perf_agent_#{i}", GenServer, [],
            capabilities: [:"cap_#{rem(i, 10)}"]
          )

        entry = %{
          id: config.id,
          config: config,
          pid: nil,
          status: :registered,
          started_at: nil,
          stopped_at: nil,
          metadata: %{},
          node: node()
        }

        assert :ok = LocalETS.register_agent(entry)
      end

      # Test search performance
      {search_time, {:ok, _found}} =
        :timer.tc(fn ->
          LocalETS.find_agents_by_capability([:cap_5])
        end)

      # Search should complete quickly even with many agents (< 10ms)
      assert search_time < 10_000

      # Test list performance
      {list_time, all_agents} =
        :timer.tc(fn ->
          LocalETS.list_all_agents()
        end)

      assert length(all_agents) == agent_count
      # List should complete quickly (< 50ms for 1000 agents)
      assert list_time < 50_000
    end

    test "error handling", %{table_name: _table} do
      # Test operations on non-existent agents
      assert {:error, :not_found} = LocalETS.get_agent(:nonexistent)
      assert {:error, :not_found} = LocalETS.update_agent_status(:nonexistent, :running, self())
      assert {:error, :not_found} = LocalETS.unregister_agent(:nonexistent)

      # Test invalid status updates
      config = Types.new_agent_config(:test_agent, GenServer, [])

      entry = %{
        id: config.id,
        config: config,
        pid: nil,
        status: :registered,
        started_at: nil,
        stopped_at: nil,
        metadata: %{},
        node: node()
      }

      assert :ok = LocalETS.register_agent(entry)

      # Should handle nil pid gracefully
      assert :ok = LocalETS.update_agent_status(:test_agent, :stopped, nil)
    end
  end

  describe "initialization and configuration" do
    test "supports custom table configuration" do
      custom_table = :"custom_test_#{:erlang.unique_integer([:positive])}"

      # Should create table with custom name
      {:ok, _} = LocalETS.init(table_name: custom_table)

      # Verify table exists and is accessible
      config = Types.new_agent_config(:custom_test, GenServer, [])

      entry = %{
        id: config.id,
        config: config,
        pid: nil,
        status: :registered,
        started_at: nil,
        stopped_at: nil,
        metadata: %{},
        node: node()
      }

      assert :ok = LocalETS.register_agent(entry)
      assert {:ok, _} = LocalETS.get_agent(:custom_test)
    end

    test "handles table recreation gracefully" do
      # Initialize twice should not cause errors
      {:ok, _} = LocalETS.init([])
      {:ok, _} = LocalETS.init([])
    end
  end
end
