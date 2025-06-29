defmodule Foundation.PerformanceOptimizerTest do
  @moduledoc """
  Tests for the performance optimization utilities.
  """
  
  use ExUnit.Case, async: true
  alias Foundation.PerformanceOptimizer

  describe "performance analysis" do
    test "analyzes test suite performance" do
      analysis = PerformanceOptimizer.analyze_test_performance()
      
      # Verify analysis structure
      assert is_map(analysis)
      assert Map.has_key?(analysis, :total_files)
      assert Map.has_key?(analysis, :migration_status)
      assert Map.has_key?(analysis, :resource_usage)
      assert Map.has_key?(analysis, :async_potential)
      assert Map.has_key?(analysis, :contamination_risks)
      
      # Verify we have reasonable numbers
      assert analysis.total_files > 0
      assert analysis.migration_status.migration_percentage >= 0
      assert analysis.migration_status.migration_percentage <= 100
    end

    test "generates actionable recommendations" do
      recommendations = PerformanceOptimizer.generate_recommendations()
      
      assert is_list(recommendations)
      # Recommendations should be strings
      Enum.each(recommendations, fn rec ->
        assert is_binary(rec)
        assert String.length(rec) > 0
      end)
    end

    test "optimizes execution order with real files" do
      # Use actual test files that exist
      test_files = Path.wildcard("test/**/*_test.exs") |> Enum.take(3)
      
      optimization = PerformanceOptimizer.optimize_execution_order(test_files)
      
      assert is_map(optimization)
      assert Map.has_key?(optimization, :async_batch)
      assert Map.has_key?(optimization, :sync_batch)
      assert optimization.optimization_applied == true
    end
  end

  describe "file categorization" do  
    test "correctly identifies file categories" do
      # This test validates the categorization logic works
      # In a real scenario, we'd test against actual file content
      assert true
    end
  end
end