defmodule Foundation.MABEAM.TypesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Foundation.MABEAM.Types

  describe "agent_config/0" do
    test "creates valid config with required fields" do
      config = Types.new_agent_config(:test_agent, GenServer, [])

      assert config.id == :test_agent
      assert config.module == GenServer
      assert config.args == []
      assert config.type == :worker
      assert is_list(config.capabilities)
      assert is_map(config.metadata)
      assert is_struct(config.created_at, DateTime)
    end

    test "accepts custom type and capabilities" do
      config =
        Types.new_agent_config(
          :ml_agent,
          MLWorker,
          [model: :bert],
          type: :ml_worker,
          capabilities: [:nlp, :classification]
        )

      assert config.type == :ml_worker
      assert :nlp in config.capabilities
      assert :classification in config.capabilities
    end

    test "validates agent_id constraints" do
      # Valid IDs
      assert {:ok, _} =
               Types.validate_agent_config(Types.new_agent_config(:valid_id, GenServer, []))

      assert {:ok, _} =
               Types.validate_agent_config(Types.new_agent_config(:"agent-123", GenServer, []))

      # Invalid IDs
      invalid_config = %{Types.new_agent_config(:test, GenServer, []) | id: "string_id"}
      assert {:error, {:invalid_agent_id, _}} = Types.validate_agent_config(invalid_config)

      nil_config = %{Types.new_agent_config(:test, GenServer, []) | id: nil}
      assert {:error, {:invalid_agent_id, _}} = Types.validate_agent_config(nil_config)
    end

    property "all agent configs are serializable" do
      check all(
              agent_id <- atom(:alphanumeric),
              module <- member_of([GenServer, Agent, Task]),
              args <- list_of(term(), max_length: 5),
              type <- member_of([:worker, :supervisor, :ml_worker]),
              capabilities <- list_of(atom(:alphanumeric), max_length: 10)
            ) do
        config =
          Types.new_agent_config(agent_id, module, args, type: type, capabilities: capabilities)

        # Test serialization roundtrip
        binary = :erlang.term_to_binary(config)
        deserialized = :erlang.binary_to_term(binary)

        assert config == deserialized
        assert {:ok, ^config} = Types.validate_agent_config(deserialized)
      end
    end
  end

  describe "universal_variable/0" do
    test "creates valid variable with required fields" do
      var = Types.new_variable(:test_var, "initial_value", :system)

      assert var.name == :test_var
      assert var.value == "initial_value"
      assert var.version == 1
      assert var.last_modifier == :system
      assert var.conflict_resolution == :last_write_wins
      assert is_struct(var.created_at, DateTime)
      assert is_struct(var.updated_at, DateTime)
    end

    test "supports different conflict resolution strategies" do
      strategies = [:last_write_wins, :consensus, {:custom, MyModule, :resolve_conflict}]

      for strategy <- strategies do
        var = Types.new_variable(:test, "value", :system, conflict_resolution: strategy)
        assert var.conflict_resolution == strategy
        assert {:ok, _} = Types.validate_variable(var)
      end
    end

    test "validates variable constraints" do
      # Valid variable
      valid_var = Types.new_variable(:valid, "value", :system)
      assert {:ok, _} = Types.validate_variable(valid_var)

      # Invalid name
      invalid_var = %{valid_var | name: nil}
      assert {:error, {:invalid_variable_name, _}} = Types.validate_variable(invalid_var)

      # Invalid version
      invalid_version = %{valid_var | version: -1}
      assert {:error, {:invalid_version, _}} = Types.validate_variable(invalid_version)
    end

    property "variables maintain version consistency" do
      check all(
              name <- atom(:alphanumeric),
              value <- term(),
              modifier <- atom(:alphanumeric)
            ) do
        var = Types.new_variable(name, value, modifier)

        # Version starts at 1
        assert var.version == 1

        # Test serialization
        binary = :erlang.term_to_binary(var)
        deserialized = :erlang.binary_to_term(binary)
        assert var == deserialized
      end
    end
  end

  describe "coordination_request/0" do
    test "creates valid coordination request" do
      request = Types.new_coordination_request(:consensus, :get_vote, %{question: "Deploy?"})

      assert request.protocol == :consensus
      assert request.type == :get_vote
      assert request.params.question == "Deploy?"
      assert is_binary(request.correlation_id)
      assert is_struct(request.created_at, DateTime)
    end

    test "generates unique correlation IDs" do
      req1 = Types.new_coordination_request(:auction, :get_bid, %{})
      req2 = Types.new_coordination_request(:auction, :get_bid, %{})

      assert req1.correlation_id != req2.correlation_id
    end

    property "coordination requests are serializable" do
      check all(
              protocol <- atom(:alphanumeric),
              type <- atom(:alphanumeric),
              params <- map_of(atom(:alphanumeric), term(), max_length: 5)
            ) do
        request = Types.new_coordination_request(protocol, type, params)

        # Test serialization roundtrip
        binary = :erlang.term_to_binary(request)
        deserialized = :erlang.binary_to_term(binary)

        assert request == deserialized
        assert {:ok, _} = Types.validate_coordination_request(deserialized)
      end
    end
  end

  describe "auction_spec/0" do
    test "creates valid sealed-bid auction spec" do
      spec = Types.new_auction_spec(:sealed_bid, :compute_resource_1, [:agent1, :agent2])

      assert spec.type == :sealed_bid
      assert spec.resource_id == :compute_resource_1
      assert spec.participants == [:agent1, :agent2]
      assert spec.starting_price == nil
      assert spec.payment_rule == :first_price
      assert is_struct(spec.created_at, DateTime)
    end

    test "creates valid English auction spec" do
      spec =
        Types.new_auction_spec(:english, :premium_slot, [:bidder1, :bidder2],
          starting_price: 10,
          increment: 1,
          max_rounds: 10
        )

      assert spec.type == :english
      assert spec.starting_price == 10
      assert spec.auction_params.increment == 1
      assert spec.auction_params.max_rounds == 10
    end

    test "creates valid Dutch auction spec" do
      spec =
        Types.new_auction_spec(:dutch, :urgent_task, [:agent1],
          starting_price: 100,
          decrement: 5,
          min_price: 20
        )

      assert spec.type == :dutch
      assert spec.starting_price == 100
      assert spec.auction_params.decrement == 5
      assert spec.auction_params.min_price == 20
    end

    test "validates auction constraints" do
      # Valid auction
      valid_auction = Types.new_auction_spec(:sealed_bid, :resource, [:agent1])
      assert {:ok, _} = Types.validate_auction_spec(valid_auction)

      # Invalid type
      invalid_type = %{valid_auction | type: :invalid_type}
      assert {:error, {:invalid_auction_type, _}} = Types.validate_auction_spec(invalid_type)

      # Empty participants
      empty_participants = %{valid_auction | participants: []}
      assert {:error, {:no_participants, _}} = Types.validate_auction_spec(empty_participants)
    end

    property "auction specs are serializable" do
      check all(
              type <- member_of([:sealed_bid, :english, :dutch]),
              resource_id <- atom(:alphanumeric),
              participants <- list_of(atom(:alphanumeric), min_length: 1, max_length: 10)
            ) do
        spec = Types.new_auction_spec(type, resource_id, participants)

        # Test serialization roundtrip
        binary = :erlang.term_to_binary(spec)
        deserialized = :erlang.binary_to_term(binary)

        assert spec == deserialized
        assert {:ok, _} = Types.validate_auction_spec(deserialized)
      end
    end
  end

  describe "type validation" do
    test "validates all core types" do
      # Agent config
      agent_config = Types.new_agent_config(:test, GenServer, [])
      assert {:ok, _} = Types.validate_agent_config(agent_config)

      # Variable
      variable = Types.new_variable(:var, "value", :system)
      assert {:ok, _} = Types.validate_variable(variable)

      # Coordination request
      coord_req = Types.new_coordination_request(:consensus, :vote, %{})
      assert {:ok, _} = Types.validate_coordination_request(coord_req)

      # Auction spec
      auction = Types.new_auction_spec(:sealed_bid, :resource, [:agent1])
      assert {:ok, _} = Types.validate_auction_spec(auction)
    end

    test "validation catches malformed structs" do
      # Missing required fields
      incomplete_config = %{id: :test}
      assert {:error, _} = Types.validate_agent_config(incomplete_config)

      incomplete_var = %{name: :test}
      assert {:error, _} = Types.validate_variable(incomplete_var)
    end
  end

  describe "constructor functions" do
    test "new_agent_config/4 with all options" do
      opts = [
        type: :coordinator,
        capabilities: [:bidding, :voting],
        metadata: %{priority: :high},
        restart_policy: :temporary
      ]

      config = Types.new_agent_config(:agent, MyModule, [:arg1], opts)

      assert config.type == :coordinator
      assert config.capabilities == [:bidding, :voting]
      assert config.metadata.priority == :high
      assert config.restart_policy == :temporary
    end

    test "new_variable/4 with all options" do
      opts = [
        conflict_resolution: :consensus,
        metadata: %{source: :ml_model},
        constraints: %{min: 0, max: 100}
      ]

      var = Types.new_variable(:param, 50, :optimizer, opts)

      assert var.conflict_resolution == :consensus
      assert var.metadata.source == :ml_model
      assert var.constraints.min == 0
      assert var.constraints.max == 100
    end
  end

  describe "performance characteristics" do
    test "constructor functions are fast" do
      {time_micro, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            Types.new_agent_config(:test, GenServer, [])
          end
        end)

      # Should take less than 1ms per 1000 constructions (1 microsecond each)
      assert time_micro < 1000
    end

    test "validation is fast" do
      config = Types.new_agent_config(:test, GenServer, [])

      {time_micro, _} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            Types.validate_agent_config(config)
          end
        end)

      # Should validate 1000 configs in less than 1ms
      assert time_micro < 1000
    end

    test "serialization overhead is minimal" do
      config = Types.new_agent_config(:test, GenServer, [])

      {time_micro, serialized} =
        :timer.tc(fn ->
          :erlang.term_to_binary(config)
        end)

      # Serialization should be very fast
      assert time_micro < 100

      # Serialized size should be reasonable (less than 1KB for basic config)
      assert byte_size(serialized) < 1024
    end
  end
end
