# test/foundation/mabeam/types_test.exs
defmodule Foundation.MABEAM.TypesTest do
  use ExUnit.Case, async: true

  alias Foundation.MABEAM.Types

  describe "agent creation" do
    test "creates agent with default values" do
      agent = Types.new_agent(:test_agent, :worker)

      assert agent.id == :test_agent
      assert agent.type == :worker
      assert agent.status == :initializing
      assert :variable_access in agent.capabilities
      assert :coordination in agent.capabilities
      assert agent.variables == %{}
      assert agent.coordination_state.leadership_status == :none
      assert is_struct(agent.metadata.created_at, DateTime)
      assert agent.metadata.node == Node.self()
    end

    test "creates coordinator agent with appropriate capabilities" do
      agent = Types.new_agent("coordinator_1", :coordinator)

      assert agent.type == :coordinator
      assert :consensus in agent.capabilities
      assert :negotiation in agent.capabilities
      assert :coordination in agent.capabilities
      assert :monitoring in agent.capabilities
    end

    test "creates agent with custom capabilities" do
      custom_capabilities = [:custom_capability, :special_feature]
      agent = Types.new_agent(:custom_agent, :worker, capabilities: custom_capabilities)

      assert agent.capabilities == custom_capabilities
    end

    test "creates agent with custom metadata" do
      opts = [
        namespace: :test_namespace,
        tags: ["test", "agent"],
        custom: %{priority: :high}
      ]

      agent = Types.new_agent(:tagged_agent, :worker, opts)

      assert agent.metadata.namespace == :test_namespace
      assert agent.metadata.tags == ["test", "agent"]
      assert agent.metadata.custom.priority == :high
    end
  end

  describe "universal variable creation" do
    test "creates variable with default values" do
      variable = Types.new_variable(:test_var, "initial_value", :creator_agent)

      assert variable.name == :test_var
      assert variable.value == "initial_value"
      assert variable.type == :shared
      assert variable.access_mode == :public
      assert variable.conflict_resolution == :last_write_wins
      assert variable.version == 1
      assert variable.last_modifier == :creator_agent
      assert is_struct(variable.last_modified, DateTime)
      assert variable.metadata.created_by == :creator_agent
      assert variable.metadata.modification_count == 1
    end

    test "creates variable with custom configuration" do
      opts = [
        type: :counter,
        access_mode: :restricted,
        conflict_resolution: :first_write_wins,
        tags: ["counter", "shared"]
      ]

      variable = Types.new_variable("custom_var", 0, "creator", opts)

      assert variable.type == :counter
      assert variable.access_mode == :restricted
      assert variable.conflict_resolution == :first_write_wins
      assert variable.metadata.tags == ["counter", "shared"]
    end

    test "creates different variable types correctly" do
      counter = Types.new_variable(:counter, 0, :agent1, type: :counter)
      flag = Types.new_variable(:flag, false, :agent2, type: :flag)
      queue = Types.new_variable(:queue, [], :agent3, type: :queue)

      assert counter.type == :counter
      assert flag.type == :flag
      assert queue.type == :queue
    end
  end

  describe "coordination request creation" do
    test "creates coordination request with default values" do
      request = Types.new_coordination_request(:consensus, :initiator, [:agent1, :agent2])

      assert request.protocol == :consensus
      assert request.initiator == :initiator
      assert request.participants == [:agent1, :agent2]
      assert request.timeout == 5000
      assert request.parameters == %{}
      assert is_binary(request.id)
      assert String.starts_with?(request.id, "req_")
      assert is_struct(request.created_at, DateTime)
    end

    test "creates coordination request with custom parameters" do
      opts = [
        id: "custom_request_id",
        parameters: %{threshold: 0.75, max_rounds: 5},
        timeout: 10_000
      ]

      request = Types.new_coordination_request(:negotiation, :leader, [:a1, :a2, :a3], opts)

      assert request.id == "custom_request_id"
      assert request.parameters.threshold == 0.75
      assert request.parameters.max_rounds == 5
      assert request.timeout == 10_000
    end

    test "creates different protocol types" do
      consensus_req = Types.new_coordination_request(:consensus, :agent1, [:agent2])
      election_req = Types.new_coordination_request(:leader_election, :agent1, [:agent2, :agent3])
      auction_req = Types.new_coordination_request(:auction, :agent1, [:agent2, :agent3, :agent4])

      assert consensus_req.protocol == :consensus
      assert election_req.protocol == :leader_election
      assert auction_req.protocol == :auction
    end
  end

  describe "message creation" do
    test "creates message with default values" do
      message = Types.new_message(:sender, :receiver, :request, %{action: "test"})

      assert message.from == :sender
      assert message.to == :receiver
      assert message.type == :request
      assert message.payload == %{action: "test"}
      assert message.priority == :normal
      assert is_binary(message.id)
      assert String.starts_with?(message.id, "msg_")
      assert is_struct(message.timestamp, DateTime)
      assert is_nil(message.reply_to)
      assert is_nil(message.correlation_id)
    end

    test "creates message with custom options" do
      opts = [
        id: "custom_message_id",
        priority: :urgent,
        reply_to: "original_message_id",
        correlation_id: "correlation_123"
      ]

      message =
        Types.new_message(:sender, [:receiver1, :receiver2], :notification, "broadcast", opts)

      assert message.id == "custom_message_id"
      assert message.to == [:receiver1, :receiver2]
      assert message.type == :notification
      assert message.payload == "broadcast"
      assert message.priority == :urgent
      assert message.reply_to == "original_message_id"
      assert message.correlation_id == "correlation_123"
    end

    test "creates different message types" do
      request = Types.new_message(:a1, :a2, :request, %{})
      response = Types.new_message(:a2, :a1, :response, %{})
      notification = Types.new_message(:a1, :a3, :notification, %{})
      coordination = Types.new_message(:a1, [:a2, :a3], :coordination, %{})

      assert request.type == :request
      assert response.type == :response
      assert notification.type == :notification
      assert coordination.type == :coordination
    end

    test "creates messages with different priorities" do
      low = Types.new_message(:a1, :a2, :request, %{}, priority: :low)
      normal = Types.new_message(:a1, :a2, :request, %{}, priority: :normal)
      high = Types.new_message(:a1, :a2, :request, %{}, priority: :high)
      urgent = Types.new_message(:a1, :a2, :request, %{}, priority: :urgent)
      system = Types.new_message(:a1, :a2, :system, %{}, priority: :system)

      assert low.priority == :low
      assert normal.priority == :normal
      assert high.priority == :high
      assert urgent.priority == :urgent
      assert system.priority == :system
    end
  end

  describe "default configuration" do
    test "provides valid default configuration" do
      config = Types.default_config()

      assert config.mode == :single_node
      assert is_map(config.coordination)
      assert is_map(config.variables)
      assert is_map(config.messaging)
      assert is_map(config.telemetry)
      assert is_map(config.timeouts)
    end

    test "coordination config has expected values" do
      config = Types.default_config()
      coord_config = config.coordination

      assert coord_config.default_timeout == 5_000
      assert coord_config.max_participants == 100
      assert coord_config.retry_attempts == 3
      assert coord_config.consensus_threshold == 0.51
      assert coord_config.leader_election_timeout == 10_000
      assert coord_config.heartbeat_interval == 1_000
    end

    test "variable config has expected values" do
      config = Types.default_config()
      var_config = config.variables

      assert var_config.default_access_mode == :public
      assert var_config.default_conflict_resolution == :last_write_wins
      assert var_config.max_variables == 10_000
      assert var_config.persistence_enabled == false
      assert var_config.backup_interval == 60_000
      assert var_config.cleanup_interval == 300_000
    end

    test "messaging config has expected values" do
      config = Types.default_config()
      msg_config = config.messaging

      assert msg_config.max_message_size == 1_048_576
      assert msg_config.message_queue_limit == 1_000
      assert msg_config.delivery_timeout == 5_000
      assert msg_config.retry_attempts == 3
      assert msg_config.compression_enabled == false
      assert msg_config.encryption_enabled == false
    end

    test "telemetry config has expected values" do
      config = Types.default_config()
      telemetry_config = config.telemetry

      assert telemetry_config.enabled == true
      assert telemetry_config.metrics_interval == 10_000
      assert telemetry_config.event_buffer_size == 1_000
      assert telemetry_config.export_format == :prometheus
      assert telemetry_config.custom_exporters == []
    end

    test "timeout config has expected values" do
      config = Types.default_config()
      timeout_config = config.timeouts

      assert timeout_config.agent_startup == 10_000
      assert timeout_config.agent_shutdown == 5_000
      assert timeout_config.coordination_default == 5_000
      assert timeout_config.variable_access == 1_000
      assert timeout_config.message_delivery == 3_000
      assert timeout_config.health_check == 2_000
    end
  end

  describe "agent type capabilities" do
    test "coordinator has appropriate default capabilities" do
      agent = Types.new_agent(:coord, :coordinator)

      assert :consensus in agent.capabilities
      assert :negotiation in agent.capabilities
      assert :coordination in agent.capabilities
      assert :monitoring in agent.capabilities
    end

    test "worker has appropriate default capabilities" do
      agent = Types.new_agent(:worker, :worker)

      assert :variable_access in agent.capabilities
      assert :coordination in agent.capabilities
    end

    test "monitor has appropriate default capabilities" do
      agent = Types.new_agent(:monitor, :monitor)

      assert :monitoring in agent.capabilities
      assert :telemetry in agent.capabilities
    end

    test "orchestrator has appropriate default capabilities" do
      agent = Types.new_agent(:orch, :orchestrator)

      assert :variable_access in agent.capabilities
      assert :coordination in agent.capabilities
      assert :consensus in agent.capabilities
    end

    test "hybrid has comprehensive capabilities" do
      agent = Types.new_agent(:hybrid, :hybrid)

      assert :consensus in agent.capabilities
      assert :negotiation in agent.capabilities
      assert :variable_access in agent.capabilities
      assert :coordination in agent.capabilities
      assert :monitoring in agent.capabilities
    end
  end

  describe "ID generation" do
    test "generates unique request IDs" do
      req1 = Types.new_coordination_request(:consensus, :a1, [:a2])
      req2 = Types.new_coordination_request(:consensus, :a1, [:a2])

      assert req1.id != req2.id
      assert String.starts_with?(req1.id, "req_")
      assert String.starts_with?(req2.id, "req_")
    end

    test "generates unique message IDs" do
      msg1 = Types.new_message(:a1, :a2, :request, %{})
      msg2 = Types.new_message(:a1, :a2, :request, %{})

      assert msg1.id != msg2.id
      assert String.starts_with?(msg1.id, "msg_")
      assert String.starts_with?(msg2.id, "msg_")
    end
  end

  describe "datetime handling" do
    test "sets timestamps correctly for agents" do
      before = DateTime.utc_now()
      agent = Types.new_agent(:time_test, :worker)
      after_time = DateTime.utc_now()

      assert DateTime.compare(agent.metadata.created_at, before) in [:gt, :eq]
      assert DateTime.compare(agent.metadata.created_at, after_time) in [:lt, :eq]
      assert agent.metadata.created_at == agent.metadata.updated_at
    end

    test "sets timestamps correctly for variables" do
      before = DateTime.utc_now()
      variable = Types.new_variable(:time_var, "value", :creator)
      after_time = DateTime.utc_now()

      assert DateTime.compare(variable.last_modified, before) in [:gt, :eq]
      assert DateTime.compare(variable.last_modified, after_time) in [:lt, :eq]
      assert variable.last_modified == variable.metadata.created_at
    end

    test "sets timestamps correctly for requests" do
      before = DateTime.utc_now()
      request = Types.new_coordination_request(:consensus, :init, [:p1])
      after_time = DateTime.utc_now()

      assert DateTime.compare(request.created_at, before) in [:gt, :eq]
      assert DateTime.compare(request.created_at, after_time) in [:lt, :eq]
    end

    test "sets timestamps correctly for messages" do
      before = DateTime.utc_now()
      message = Types.new_message(:sender, :receiver, :request, %{})
      after_time = DateTime.utc_now()

      assert DateTime.compare(message.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(message.timestamp, after_time) in [:lt, :eq]
    end
  end
end
