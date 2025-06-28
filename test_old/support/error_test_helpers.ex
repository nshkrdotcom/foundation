defmodule Foundation.ErrorTestHelpers do
  @moduledoc """
  Test helpers for validating error handling patterns.
  """

  alias Foundation.Error
  import ExUnit.Assertions

  @doc """
  Asserts that a result is an error with specific characteristics.
  """
  defmacro assert_error(result, expected_code) do
    quote do
      case unquote(result) do
        {:error, %Error{code: code} = error} ->
          assert code == unquote(expected_code),
                 "Expected error code #{unquote(expected_code)}, got #{code}"

          error

        {:error, other} ->
          flunk("Expected Error struct, got: #{inspect(other)}")

        {:ok, value} ->
          flunk("Expected error, got success: #{inspect(value)}")

        other ->
          flunk("Expected error tuple, got: #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts that a result is successful.
  """
  defmacro assert_ok(result) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          value

        {:error, %Error{} = error} ->
          flunk("Expected success, got error: #{Error.to_string(error)}")

        {:error, reason} ->
          flunk("Expected success, got error: #{inspect(reason)}")

        other ->
          flunk("Expected {:ok, value} tuple, got: #{inspect(other)}")
      end
    end
  end

  @doc """
  Tests that a function properly handles various error conditions.
  """
  def test_error_scenarios(fun, scenarios) do
    Enum.each(scenarios, fn {input, expected_error_code} ->
      result = fun.(input)
      assert_error(result, expected_error_code)
    end)
  end
end
