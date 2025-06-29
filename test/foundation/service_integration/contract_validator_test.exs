defmodule Foundation.ServiceIntegration.ContractValidatorTest do
  use ExUnit.Case, async: false
  
  alias Foundation.ServiceIntegration.ContractValidator
  alias Foundation.ServiceIntegration.ContractEvolution

  describe "ContractValidator" do
    test "starts and stops cleanly" do
      {:ok, pid} = ContractValidator.start_link(name: :test_contract_validator)
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "validates Discovery contracts with evolution support" do
      {:ok, _pid} = ContractValidator.start_link(
        name: :test_contract_validator_evolution,
        enable_auto_validation: false
      )
      
      # Force validation
      result = GenServer.call(:test_contract_validator_evolution, :validate_all_contracts, 10_000)
      
      assert {:ok, validation_result} = result
      assert is_map(validation_result)
      assert Map.has_key?(validation_result, :mabeam)
      assert Map.has_key?(validation_result, :status)
      
      # Should handle MABEAM.Discovery evolution gracefully
      assert validation_result.status in [:all_valid, :evolution_detected]
      
      GenServer.stop(:test_contract_validator_evolution)
    end

    test "registers and validates custom contracts" do
      {:ok, _pid} = ContractValidator.start_link(
        name: :test_contract_validator_custom,
        enable_auto_validation: false
      )
      
      # Register a simple custom contract
      :ok = GenServer.call(:test_contract_validator_custom, {
        :register_contract, 
        TestModule, 
        fn _module -> :ok end, 
        []
      })
      
      # Validate all contracts including custom
      {:ok, result} = GenServer.call(:test_contract_validator_custom, :validate_all_contracts)
      
      assert result.custom == :all_custom_contracts_valid
      
      GenServer.stop(:test_contract_validator_custom)
    end

    test "handles validation exceptions gracefully" do
      {:ok, _pid} = ContractValidator.start_link(
        name: :test_contract_validator_exception,
        enable_auto_validation: false
      )
      
      # Register a contract validator that raises an exception
      :ok = GenServer.call(:test_contract_validator_exception, {
        :register_contract,
        ErrorModule,
        fn _module -> raise "Test exception" end,
        []
      })
      
      # Should handle the exception and return an error
      {:ok, result} = GenServer.call(:test_contract_validator_exception, :validate_all_contracts)
      
      assert {:error, {:custom_contract_violations, violations}} = result.custom
      assert length(violations) == 1
      assert {ErrorModule, {:validator_exception, %RuntimeError{}}} = hd(violations)
      
      GenServer.stop(:test_contract_validator_exception)
    end

    test "tracks validation timing and results" do
      {:ok, _pid} = ContractValidator.start_link(
        name: :test_contract_validator_timing,
        enable_auto_validation: false
      )
      
      {:ok, result} = GenServer.call(:test_contract_validator_timing, :validate_all_contracts)
      
      assert Map.has_key?(result, :timestamp)
      assert Map.has_key?(result, :validation_time_ms)
      assert is_integer(result.validation_time_ms)
      assert result.validation_time_ms >= 0
      
      GenServer.stop(:test_contract_validator_timing)
    end
  end

  describe "ContractEvolution" do
    test "validates Discovery function evolution" do
      # MABEAM.Discovery should support evolved signatures (arity 2, 3, 3)
      result = ContractEvolution.validate_discovery_functions(MABEAM.Discovery)
      assert result == true
    end

    test "checks individual function evolution" do
      status = ContractEvolution.check_function_evolution(
        Foundation.Services.RetryService,
        :start_link,
        legacy_arity: 0,
        evolved_arity: 1
      )
      
      # Should be :both_supported since we support both arity 0 and arity 1
      assert status == :both_supported
    end

    test "analyzes complete module evolution" do
      status = ContractEvolution.analyze_module_evolution(Foundation.Services.RetryService, [
        {:start_link, legacy_arity: 0, evolved_arity: 1}
      ])
      
      assert is_map(status)
      assert Map.has_key?(status, :overall_status)
      assert Map.has_key?(status, :start_link)
      
      # Function should be both supported (legacy arity 0 + evolved arity 1)
      assert status.start_link == :both_supported
      assert status.overall_status == :fully_compatible
    end

    test "provides migration suggestions" do
      suggestions = ContractEvolution.migration_suggestions(:evolved_only)
      
      assert is_list(suggestions)
      assert length(suggestions) > 0
      assert Enum.any?(suggestions, &String.contains?(&1, "contract tests"))
    end

    test "creates compatibility wrapper code" do
      wrapper_code = ContractEvolution.create_compatibility_wrapper(
        :find_capable_and_healthy,
        legacy_params: [:capability],
        evolved_params: [:capability, :impl],
        default_values: [impl: nil]
      )
      
      assert is_binary(wrapper_code)
      assert String.contains?(wrapper_code, "find_capable_and_healthy(capability)")
      assert String.contains?(wrapper_code, "find_capable_and_healthy_evolved")
    end
  end
end