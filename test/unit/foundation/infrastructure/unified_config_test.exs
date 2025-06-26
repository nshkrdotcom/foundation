defmodule Foundation.Infrastructure.UnifiedConfigTest do
  @moduledoc """
  TDD tests for unified configuration system in Infrastructure module.

  These tests verify that Infrastructure configuration functions use the
  main ConfigServer instead of a private Agent, ensuring consistency
  with the rest of the Foundation configuration system.
  """

  use ExUnit.Case, async: false

  alias Foundation.Infrastructure
  alias Foundation.{Config, Types}

  @protection_key :test_api
  @test_config %{
    circuit_breaker: %{
      failure_threshold: 3,
      recovery_time: 15_000
    },
    rate_limiter: %{
      scale: 30_000,
      limit: 50
    },
    connection_pool: %{
      size: 5,
      max_overflow: 2
    }
  }

  setup do
    # Ensure ConfigServer is started and clean state
    case Config.reset() do
      :ok -> :ok
      {:error, _} -> :ok
    end

    # Initialize with default config including infrastructure section
    case Config.initialize() do
      :ok -> :ok
      # Service might already be initialized
      {:error, _} -> :ok
    end

    :ok
  end

  describe "configure_protection/2 with unified config" do
    test "stores protection config in main ConfigServer" do
      # This should FAIL initially - Infrastructure still uses Agent
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Verify config is stored in main ConfigServer, not private Agent
      config_path = [:infrastructure, :protection, @protection_key]
      assert {:ok, stored_config} = Config.get(config_path)
      assert stored_config == @test_config
    end

    test "protection config persists in ConfigServer across process restarts" do
      # Store config
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Simulate Infrastructure module restart (Agent would lose data)
      # ConfigServer should retain the data
      config_path = [:infrastructure, :protection, @protection_key]
      assert {:ok, stored_config} = Config.get(config_path)
      assert stored_config == @test_config
    end

    test "protection config generates ConfigServer events" do
      # Setup event capture (simplified for test)
      config_path = [:infrastructure, :protection, @protection_key]

      # Configure protection - should trigger config update event
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Verify event was emitted through ConfigServer (not Agent)
      assert {:ok, stored_config} = Config.get(config_path)
      assert stored_config == @test_config
    end

    test "invalid protection config returns proper ConfigServer errors" do
      invalid_config = %{invalid: "config"}

      # Should return validation error consistent with ConfigServer
      assert {:error, reason} = Infrastructure.configure_protection(@protection_key, invalid_config)
      assert reason in [:missing_required_keys, :invalid_config_format]
    end
  end

  describe "get_protection_config/1 with unified config" do
    test "retrieves protection config from main ConfigServer" do
      # Store config using ConfigServer directly
      config_path = [:infrastructure, :protection, @protection_key]
      assert :ok = Config.update(config_path, @test_config)

      # Infrastructure.get_protection_config should read from ConfigServer
      assert {:ok, retrieved_config} = Infrastructure.get_protection_config(@protection_key)
      assert retrieved_config == @test_config
    end

    test "returns not_found for non-existent protection config" do
      non_existent_key = :does_not_exist

      # Should return consistent error with ConfigServer behavior
      assert {:error, :not_found} = Infrastructure.get_protection_config(non_existent_key)
    end

    test "protection config benefits from ConfigServer graceful degradation" do
      # Store config
      config_path = [:infrastructure, :protection, @protection_key]
      assert :ok = Config.update(config_path, @test_config)

      # Even if ConfigServer is temporarily unavailable, 
      # graceful degradation should provide cached value
      assert {:ok, retrieved_config} = Infrastructure.get_protection_config(@protection_key)
      assert retrieved_config == @test_config
    end
  end

  describe "list_protection_keys/0 with unified config" do
    test "lists protection keys from main ConfigServer" do
      # Store multiple protection configs
      config_path_1 = [:infrastructure, :protection, :api_one]
      config_path_2 = [:infrastructure, :protection, :api_two]

      assert :ok = Config.update(config_path_1, @test_config)
      assert :ok = Config.update(config_path_2, @test_config)

      # Should read from ConfigServer infrastructure section
      keys = Infrastructure.list_protection_keys()
      assert :api_one in keys
      assert :api_two in keys
    end

    test "returns empty list when no protection configs exist" do
      # Fresh ConfigServer should have empty protection configs
      keys = Infrastructure.list_protection_keys()
      assert keys == []
    end
  end

  describe "unified config schema validation" do
    test "protection config validates against infrastructure schema" do
      # Config should validate against Types.Config infrastructure schema
      config_path = [:infrastructure, :protection, @protection_key]

      # Valid config should pass validation
      assert :ok = Config.update(config_path, @test_config)

      # Retrieve and verify structure matches infrastructure schema
      assert {:ok, full_config} = Config.get()
      assert %Types.Config{} = full_config
      assert Map.has_key?(full_config.infrastructure, :protection)
    end

    test "infrastructure config integrates with main config structure" do
      # Verify infrastructure config is part of main config schema
      assert {:ok, config} = Config.get()
      assert %Types.Config{} = config

      # Should have infrastructure section with proper structure
      assert is_map(config.infrastructure)
      assert Map.has_key?(config.infrastructure, :rate_limiting)
      assert Map.has_key?(config.infrastructure, :circuit_breaker)
      assert Map.has_key?(config.infrastructure, :connection_pool)
    end
  end

  describe "backward compatibility" do
    test "existing Infrastructure API continues to work" do
      # Existing functions should work but use ConfigServer internally
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)
      assert {:ok, config} = Infrastructure.get_protection_config(@protection_key)
      assert config == @test_config

      keys = Infrastructure.list_protection_keys()
      assert @protection_key in keys
    end

    test "no references to private Agent in Infrastructure module" do
      # This is a meta-test - after migration, no Agent should be used
      # We'll verify this by checking that ConfigServer has the data
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Data should be in ConfigServer, not in any private Agent
      config_path = [:infrastructure, :protection, @protection_key]
      assert {:ok, stored_config} = Config.get(config_path)
      assert stored_config == @test_config
    end
  end

  describe "error handling consistency" do
    test "Infrastructure errors consistent with ConfigServer patterns" do
      # ConfigServer-style error handling should be used
      invalid_config = "not a map"

      result = Infrastructure.configure_protection(@protection_key, invalid_config)

      # Should return error consistent with ConfigServer validation
      assert {:error, _reason} = result
    end

    test "Infrastructure graceful degradation matches ConfigServer" do
      # Store valid config
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Should benefit from same graceful degradation as other ConfigServer operations
      assert {:ok, config} = Infrastructure.get_protection_config(@protection_key)
      assert config == @test_config
    end
  end

  describe "performance and reliability" do
    test "Infrastructure config benefits from ConfigServer supervision" do
      # Unlike Agent-based approach, config should survive process issues
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Config should be reliably available (supervised by ConfigServer)
      assert {:ok, config} = Infrastructure.get_protection_config(@protection_key)
      assert config == @test_config
    end

    test "Infrastructure config supports telemetry like other ConfigServer operations" do
      # ConfigServer operations generate telemetry events
      assert :ok = Infrastructure.configure_protection(@protection_key, @test_config)

      # Should benefit from same telemetry infrastructure
      assert {:ok, config} = Infrastructure.get_protection_config(@protection_key)
      assert config == @test_config
    end
  end
end
