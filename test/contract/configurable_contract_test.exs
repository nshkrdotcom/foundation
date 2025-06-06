defmodule Foundation.Contract.ConfigurableContractTest do
  @moduledoc """
  Contract tests for Foundation.Contracts.Configurable behavior.

  Verifies that implementations correctly follow the Configurable contract,
  including proper return types, error handling, and API compliance.
  """

  use ExUnit.Case, async: false

  alias Foundation.Contracts.Configurable
  alias Foundation.Services.ConfigServer
  alias Foundation.Types.{Config, Error}
  alias Foundation.ContractTestHelpers

  @moduletag :contract

  # Test the default implementation: Foundation.Services.ConfigServer
  @implementation_module ConfigServer
  @behavior_module Configurable

  setup do
    # Ensure service is available for testing
    Foundation.TestHelpers.ensure_config_available()

    # Reset to clean state
    :ok = @implementation_module.reset()

    :ok
  end

  describe "Configurable Behavior Contract for #{@implementation_module}" do
    test "module properly implements the Configurable behavior" do
      result =
        ContractTestHelpers.validate_behavior_implementation(
          @implementation_module,
          @behavior_module
        )

      assert result == :ok, "Module should implement all required behavior callbacks"
    end

    test "get/0 returns a valid Config struct or an error" do
      result = @implementation_module.get()

      assert match?({:ok, %Config{}}, result) or match?({:error, %Error{}}, result),
             "get/0 should return {:ok, Config.t()} or {:error, Error.t()}"

      case result do
        {:ok, config} ->
          assert %Config{} = config
          assert Map.has_key?(config, :ai)
          assert Map.has_key?(config, :dev)

        {:error, error} ->
          assert %Error{} = error
          assert is_atom(error.error_type)
      end
    end

    test "get/1 returns a value for a valid path and an error for an invalid one" do
      # Test with valid paths
      valid_paths = [
        [:dev, :debug_mode],
        [:ai, :provider],
        [:ai, :planning, :sampling_rate]
      ]

      Enum.each(valid_paths, fn path ->
        result = @implementation_module.get(path)

        assert match?({:ok, _}, result) or match?({:error, %Error{}}, result),
               "get/1 should return {:ok, value} or {:error, Error.t()} for path #{inspect(path)}"
      end)

      # Test with invalid paths
      invalid_paths = [
        [:nonexistent],
        [:ai, :nonexistent],
        [:very, :deeply, :nested, :nonexistent, :path]
      ]

      Enum.each(invalid_paths, fn path ->
        result = @implementation_module.get(path)

        assert match?({:error, %Error{error_type: :config_path_not_found}}, result),
               "get/1 should return path not found error for invalid path #{inspect(path)}"
      end)
    end

    test "update/2 succeeds for updatable paths and fails for forbidden ones" do
      # Get list of updatable paths
      updatable_paths = @implementation_module.updatable_paths()
      assert is_list(updatable_paths), "updatable_paths/0 should return a list"
      assert length(updatable_paths) > 0, "should have at least some updatable paths"

      # Test updating a known updatable path
      if [:dev, :debug_mode] in updatable_paths do
        result = @implementation_module.update([:dev, :debug_mode], true)
        assert result == :ok, "should allow updating debug_mode"

        # Verify the update was applied
        {:ok, value} = @implementation_module.get([:dev, :debug_mode])
        assert value == true
      end

      # Test forbidden paths (from Foundation.Config module)
      forbidden_paths = [
        [:ai, :api_key],
        [:storage, :encryption_key],
        [:security],
        [:system, :node_name]
      ]

      Enum.each(forbidden_paths, fn path ->
        result = @implementation_module.update(path, "test_value")

        assert match?({:error, %Error{}}, result),
               "should reject updates to forbidden path #{inspect(path)}"
      end)
    end

    test "validate/1 correctly validates or rejects a Config struct" do
      # Test with valid config
      {:ok, valid_config} = @implementation_module.get()
      result = @implementation_module.validate(valid_config)
      assert result == :ok, "should validate a proper Config struct"

      # Test with invalid config structures
      # The validator should either return an error tuple or raise an exception
      invalid_configs = [
        # Wrong type for ai section
        %Config{ai: "not_a_map"},
        # Wrong type for provider
        %Config{ai: %{provider: 123}}
      ]

      Enum.each(invalid_configs, fn invalid_config ->
        try do
          result = @implementation_module.validate(invalid_config)
          # If it returns a result, it should be an error
          assert match?({:error, %Error{}}, result),
                 "should reject invalid config: #{inspect(invalid_config, limit: 3)}"
        rescue
          FunctionClauseError ->
            # Function clause errors are also acceptable for invalid configs
            :ok
        end
      end)

      # Test with completely invalid structure (should cause function clause error)
      assert_raise FunctionClauseError, fn ->
        @implementation_module.validate(%{})
      end
    end

    test "updatable_paths/0 returns a list of lists of atoms" do
      result = @implementation_module.updatable_paths()

      assert is_list(result), "should return a list"

      Enum.each(result, fn path ->
        assert is_list(path), "each path should be a list"
        assert length(path) > 0, "each path should be non-empty"

        Enum.each(path, fn segment ->
          assert is_atom(segment), "each path segment should be an atom"
        end)
      end)
    end

    test "reset/0 restores the configuration to a default state" do
      # Make a change
      updatable_paths = @implementation_module.updatable_paths()

      if [:dev, :debug_mode] in updatable_paths do
        # Change debug mode
        :ok = @implementation_module.update([:dev, :debug_mode], true)
        {:ok, changed_value} = @implementation_module.get([:dev, :debug_mode])
        assert changed_value == true

        # Reset configuration
        result = @implementation_module.reset()
        assert result == :ok, "reset/0 should return :ok"

        # Verify reset worked - debug_mode should be back to default (false)
        {:ok, reset_value} = @implementation_module.get([:dev, :debug_mode])
        assert reset_value == false, "debug_mode should be reset to default value"
      end
    end

    test "available?/0 returns a boolean" do
      result = @implementation_module.available?()
      assert is_boolean(result), "available?/0 should return a boolean"
      assert result == true, "service should be available during tests"
    end
  end

  describe "Contract API Documentation and Typespecs" do
    test "implementation module has proper documentation" do
      assert ContractTestHelpers.has_documentation?(@implementation_module),
             "#{@implementation_module} should have module documentation"
    end

    test "implementation module has typespecs for public functions" do
      assert ContractTestHelpers.has_typespecs?(@implementation_module),
             "#{@implementation_module} should have typespecs for public functions"
    end

    test "behavior module has proper documentation" do
      assert ContractTestHelpers.has_documentation?(@behavior_module),
             "#{@behavior_module} should have module documentation"
    end
  end

  describe "Error Handling Contract" do
    test "all error returns use Foundation.Types.Error struct" do
      # Test error conditions
      error_result = @implementation_module.get([:nonexistent, :path])

      case error_result do
        {:error, error} ->
          assert %Error{} = error
          assert is_atom(error.error_type)
          assert is_binary(error.message)
          assert error.error_type == :config_path_not_found

        other ->
          flunk("Expected error result, got: #{inspect(other)}")
      end
    end

    test "errors contain meaningful context information" do
      error_result = @implementation_module.update([:ai, :api_key], "forbidden")

      case error_result do
        {:error, error} ->
          assert %Error{} = error
          assert error.message != ""
          assert is_map(error.context) or is_nil(error.context)

        other ->
          flunk("Expected error result, got: #{inspect(other)}")
      end
    end
  end
end
