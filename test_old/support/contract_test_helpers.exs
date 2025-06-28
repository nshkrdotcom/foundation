defmodule Foundation.ContractTestHelpers do
  @moduledoc """
  Helper utilities for contract testing.

  Provides common utilities for testing behavior implementations
  and validating contract compliance.
  """

  @doc """
  Validates that a module properly implements a behavior contract.
  """
  @spec validate_behavior_implementation(module(), module()) :: :ok | {:error, [atom()]}
  def validate_behavior_implementation(implementation_module, behavior_module) do
    behavior_callbacks = behavior_module.behaviour_info(:callbacks)
    implementation_exports = implementation_module.__info__(:functions)

    missing_functions =
      behavior_callbacks
      |> Enum.filter(fn callback -> callback not in implementation_exports end)

    if missing_functions == [] do
      :ok
    else
      {:error, missing_functions}
    end
  end

  @doc """
  Validates that a function returns values matching the expected typespec.
  """
  @spec validate_return_type(term(), atom()) :: boolean()
  def validate_return_type(result, expected_type) do
    case {result, expected_type} do
      {{:ok, _}, :ok_tuple} -> true
      {{:error, _}, :error_tuple} -> true
      {result, :boolean} when is_boolean(result) -> true
      {result, :map} when is_map(result) -> true
      {result, :list} when is_list(result) -> true
      _ -> false
    end
  end

  @doc """
  Creates a test configuration for contract testing.
  """
  @spec create_test_config() :: map()
  def create_test_config do
    %{
      ai: %{provider: :mock, api_key: "test-key"},
      dev: %{debug_mode: true},
      test: %{contract_testing: true}
    }
  end

  @doc """
  Validates that a module has proper documentation.
  """
  @spec has_documentation?(module()) :: boolean()
  def has_documentation?(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, module_doc, _, _} -> module_doc != :none
      _ -> false
    end
  end

  @doc """
  Validates that public functions have typespecs.
  """
  @spec has_typespecs?(module()) :: boolean()
  def has_typespecs?(module) do
    try do
      case Code.Typespec.fetch_specs(module) do
        {:ok, specs} -> length(specs) > 0
        :error -> false
      end
    rescue
      _ -> false
    end
  end
end
