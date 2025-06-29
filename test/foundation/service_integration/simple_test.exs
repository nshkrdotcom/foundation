defmodule Foundation.ServiceIntegration.SimpleTest do
  use ExUnit.Case, async: false
  
  test "can load the main ServiceIntegration module" do
    assert Code.ensure_loaded?(Foundation.ServiceIntegration)
  end

  test "can call integration_status" do
    {:ok, status} = Foundation.ServiceIntegration.integration_status()
    assert is_map(status)
    assert Map.has_key?(status, :timestamp)
  end

  test "can load ContractEvolution module" do
    # Try to load the module explicitly
    case Code.ensure_compiled(Foundation.ServiceIntegration.ContractEvolution) do
      {:module, module} ->
        assert module == Foundation.ServiceIntegration.ContractEvolution
      {:error, reason} ->
        flunk("ContractEvolution failed to compile: #{inspect(reason)}")
    end
  end

  test "can load ContractValidator module" do
    # Try to load the module explicitly
    case Code.ensure_compiled(Foundation.ServiceIntegration.ContractValidator) do
      {:module, module} ->
        assert module == Foundation.ServiceIntegration.ContractValidator
      {:error, reason} ->
        flunk("ContractValidator failed to compile: #{inspect(reason)}")
    end
  end
end