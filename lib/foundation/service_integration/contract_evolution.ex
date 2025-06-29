defmodule Foundation.ServiceIntegration.ContractEvolution do
  @moduledoc """
  Handles service contract evolution and migration.

  This module provides utilities for managing API evolution without breaking
  existing contracts. It's specifically designed to address Category 3 contract
  violations where service APIs evolve (e.g., adding `impl` parameters) but
  existing code expects the legacy signatures.

  ## Purpose

  Service APIs evolve over time. This module provides:
  - Detection of contract evolution scenarios
  - Validation of both legacy and evolved contract signatures
  - Migration assistance for contract evolution
  - Graceful fallback strategies

  ## Contract Evolution Patterns

  ### 1. Parameter Addition
  Functions gain additional optional parameters:
  ```elixir
  # Legacy: find_capable_and_healthy(capability)
  # Evolved: find_capable_and_healthy(capability, impl \\\\ nil)
  ```

  ### 2. Return Format Evolution  
  Return values become more structured:
  ```elixir
  # Legacy: [agents]
  # Evolved: {:ok, [agents]} | {:error, reason}
  ```

  ### 3. Arity Changes
  Function signatures change completely:
  ```elixir
  # Legacy: find_least_loaded_agents(capability)
  # Evolved: find_least_loaded_agents(capability, count, impl)
  ```

  ## Usage

      # Validate Discovery functions support either legacy or evolved signatures
      case ContractEvolution.validate_discovery_functions(MABEAM.Discovery) do
        true -> :contract_valid
        false -> :contract_evolution_required
      end

      # Check specific function evolution
      evolution_status = ContractEvolution.check_function_evolution(
        MABEAM.Discovery, 
        :find_capable_and_healthy, 
        legacy_arity: 1, 
        evolved_arity: 2
      )
  """

  require Logger

  @type evolution_status :: :legacy_only | :evolved_only | :both_supported | :neither_supported
  @type function_spec :: {atom(), non_neg_integer()}

  @doc """
  Validates that Discovery service functions support either legacy or evolved contracts.

  This specifically addresses Category 3 Discovery contract arity mismatches where
  contract tests expect different arities than the current implementation provides.

  ## Discovery Function Evolution

  - `find_capable_and_healthy`: 1 → 2 (added `impl` parameter)
  - `find_agents_with_resources`: 2 → 3 (added `impl` parameter)  
  - `find_least_loaded_agents`: 1 → 3 (added `count` and `impl` parameters)

  ## Returns

  - `true` - At least one signature set (legacy or evolved) is fully supported
  - `false` - Neither legacy nor evolved signatures are fully supported
  """
  @spec validate_discovery_functions(module()) :: boolean()
  def validate_discovery_functions(discovery_module) do
    legacy_functions = [
      {:find_capable_and_healthy, 1},
      {:find_agents_with_resources, 2},
      {:find_least_loaded_agents, 1}
    ]

    evolved_functions = [
      {:find_capable_and_healthy, 2},
      {:find_agents_with_resources, 3},
      {:find_least_loaded_agents, 3}
    ]

    # Module must support either ALL legacy functions OR ALL evolved functions
    legacy_supported = validate_function_set(discovery_module, legacy_functions)
    evolved_supported = validate_function_set(discovery_module, evolved_functions)

    result = legacy_supported or evolved_supported

    log_discovery_validation_result(discovery_module, {legacy_supported, evolved_supported}, result)

    result
  end

  @doc """
  Checks the evolution status of a specific function.

  ## Parameters

  - `module` - The module to check
  - `function_name` - The function name (atom)
  - `opts` - Options including `:legacy_arity` and `:evolved_arity`

  ## Returns

  - `:legacy_only` - Only legacy arity is supported
  - `:evolved_only` - Only evolved arity is supported  
  - `:both_supported` - Both arities are supported
  - `:neither_supported` - Neither arity is supported
  """
  @spec check_function_evolution(module(), atom(), keyword()) :: evolution_status()
  def check_function_evolution(module, function_name, opts) do
    legacy_arity = Keyword.get(opts, :legacy_arity)
    evolved_arity = Keyword.get(opts, :evolved_arity)

    legacy_exists = legacy_arity && function_exported?(module, function_name, legacy_arity)
    evolved_exists = evolved_arity && function_exported?(module, function_name, evolved_arity)

    case {legacy_exists, evolved_exists} do
      {true, true} -> :both_supported
      {true, false} -> :legacy_only
      {false, true} -> :evolved_only
      {false, false} -> :neither_supported
    end
  end

  @doc """
  Analyzes the complete evolution status of a module's functions.

  Returns detailed information about which functions support legacy, evolved, 
  or both signature formats.

  ## Example

      status = ContractEvolution.analyze_module_evolution(MABEAM.Discovery, [
        {:find_capable_and_healthy, legacy_arity: 1, evolved_arity: 2},
        {:find_agents_with_resources, legacy_arity: 2, evolved_arity: 3},
        {:find_least_loaded_agents, legacy_arity: 1, evolved_arity: 3}
      ])
      
      # Returns:
      # %{
      #   find_capable_and_healthy: :evolved_only,
      #   find_agents_with_resources: :evolved_only,
      #   find_least_loaded_agents: :evolved_only,
      #   overall_status: :fully_evolved
      # }
  """
  @spec analyze_module_evolution(module(), [{atom(), keyword()}]) :: map()
  def analyze_module_evolution(module, function_specs) do
    function_status =
      Enum.into(function_specs, %{}, fn {function_name, opts} ->
        status = check_function_evolution(module, function_name, opts)
        {function_name, status}
      end)

    overall_status = determine_overall_evolution_status(Map.values(function_status))

    Map.put(function_status, :overall_status, overall_status)
  end

  @doc """
  Provides migration suggestions for contract evolution.

  Given the current evolution status, suggests actions for maintaining
  backwards compatibility or completing evolution.
  """
  @spec migration_suggestions(evolution_status()) :: [String.t()]
  def migration_suggestions(evolution_status) do
    case evolution_status do
      :legacy_only ->
        [
          "Consider adding evolved function signatures for future compatibility",
          "Implement default parameter values to support both arities",
          "Add @spec declarations for both legacy and evolved signatures"
        ]

      :evolved_only ->
        [
          "Update contract tests to use evolved function signatures",
          "Consider providing legacy wrapper functions for backwards compatibility",
          "Update documentation to reflect the evolved API"
        ]

      :both_supported ->
        [
          "Excellent! Both legacy and evolved signatures are supported",
          "Consider deprecating legacy signatures in future versions",
          "Ensure test coverage for both signature formats"
        ]

      :neither_supported ->
        [
          "Function does not exist or has unexpected arity",
          "Verify function name and module are correct",
          "Check if function has been renamed or moved"
        ]
    end
  end

  @doc """
  Creates a compatibility wrapper for evolved functions.

  This helps maintain backwards compatibility when functions have evolved
  beyond their original signatures.

  ## Example

      # For find_capable_and_healthy(capability, impl \\\\ nil)
      # Create wrapper: find_capable_and_healthy(capability)
      
      wrapper_code = ContractEvolution.create_compatibility_wrapper(
        :find_capable_and_healthy,
        legacy_params: [:capability],
        evolved_params: [:capability, :impl],
        default_values: [impl: nil]
      )
  """
  @spec create_compatibility_wrapper(atom(), keyword()) :: String.t()
  def create_compatibility_wrapper(function_name, opts) do
    legacy_params = Keyword.get(opts, :legacy_params, [])
    evolved_params = Keyword.get(opts, :evolved_params, [])
    default_values = Keyword.get(opts, :default_values, [])

    legacy_param_str = Enum.join(legacy_params, ", ")

    evolved_args =
      Enum.map(evolved_params, fn param ->
        case Keyword.get(default_values, param) do
          nil -> to_string(param)
          default_val -> "#{param} \\\\ #{inspect(default_val)}"
        end
      end)

    evolved_param_str = Enum.join(evolved_args, ", ")

    call_args =
      Enum.map(evolved_params, fn param ->
        case Keyword.get(default_values, param) do
          nil ->
            to_string(param)

          default_val ->
            if param in legacy_params do
              to_string(param)
            else
              inspect(default_val)
            end
        end
      end)

    call_args_str = Enum.join(call_args, ", ")

    """
    # Legacy compatibility wrapper for #{function_name}
    def #{function_name}(#{legacy_param_str}) do
      #{function_name}_evolved(#{call_args_str})
    end

    # Evolved function (rename existing implementation)
    def #{function_name}_evolved(#{evolved_param_str}) do
      # ... existing implementation ...
    end
    """
  end

  ## Private Functions

  defp validate_function_set(module, functions) do
    # Ensure module is loaded before checking exports
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        Enum.all?(functions, fn {func, arity} ->
          function_exported?(module, func, arity)
        end)

      {:error, _reason} ->
        false
    end
  end

  defp log_discovery_validation_result(
         discovery_module,
         {legacy_supported, evolved_supported},
         overall_result
       ) do
    case {legacy_supported, evolved_supported} do
      {true, true} ->
        Logger.info("Discovery module supports both legacy and evolved contracts",
          module: discovery_module,
          status: :both_supported
        )

      {true, false} ->
        Logger.info("Discovery module supports legacy contracts only",
          module: discovery_module,
          status: :legacy_only
        )

      {false, true} ->
        Logger.info("Discovery module supports evolved contracts only",
          module: discovery_module,
          status: :evolved_only
        )

      {false, false} ->
        Logger.warning("Discovery module supports neither legacy nor evolved contracts",
          module: discovery_module,
          status: :neither_supported
        )
    end

    if not overall_result do
      Logger.error("Discovery contract validation failed - no supported signature set",
        module: discovery_module,
        legacy_supported: legacy_supported,
        evolved_supported: evolved_supported
      )
    end
  end

  defp determine_overall_evolution_status(function_statuses) do
    cond do
      Enum.all?(function_statuses, &(&1 == :evolved_only)) ->
        :fully_evolved

      Enum.all?(function_statuses, &(&1 == :legacy_only)) ->
        :fully_legacy

      Enum.all?(function_statuses, &(&1 == :both_supported)) ->
        :fully_compatible

      Enum.any?(function_statuses, &(&1 == :neither_supported)) ->
        :partially_broken

      true ->
        :mixed_evolution
    end
  end
end
