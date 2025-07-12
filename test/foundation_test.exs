defmodule FoundationTest do
  use ExUnit.Case
  doctest Foundation
  
  describe "Foundation application" do
    test "starts successfully" do
      # Foundation should start with Jido-native architecture
      case Foundation.start(:normal, []) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
      
      # Verify Jido is running
      assert :ok = Application.ensure_started(:jido)
      
      # Clean up
      :ok = Application.stop(:foundation)
    end
  end
end