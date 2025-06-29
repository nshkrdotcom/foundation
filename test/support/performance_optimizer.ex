defmodule Foundation.PerformanceOptimizer do
  @moduledoc """
  Performance optimization utilities for the Foundation test suite.
  
  This module provides tools and strategies to optimize test performance,
  reduce resource conflicts, and improve overall test suite reliability.
  """

  require Logger

  @doc """
  Analyzes test suite performance and provides optimization recommendations.
  """
  def analyze_test_performance do
    {time, result} = :timer.tc(fn ->
      %{
        total_files: count_test_files(),
        migration_status: analyze_migration_status(),
        resource_usage: analyze_resource_usage(),
        async_potential: analyze_async_potential(),
        contamination_risks: analyze_contamination_risks()
      }
    end)
    
    Logger.info("Test suite analysis completed in #{time / 1000}ms")
    result
  end

  @doc """
  Optimizes test execution order to minimize resource conflicts.
  """
  def optimize_execution_order(test_files) do
    test_files
    |> Enum.map(&categorize_test_file/1)
    |> sort_by_resource_requirements()
    |> optimize_async_grouping()
  end

  @doc """
  Provides performance recommendations based on current test suite state.
  """
  def generate_recommendations do
    analysis = analyze_test_performance()
    
    recommendations = []
    
    # Check migration status
    recommendations = if analysis.migration_status.unmigrated_high_risk > 0 do
      ["Migrate #{analysis.migration_status.unmigrated_high_risk} high-risk files to UnifiedTestFoundation" | recommendations]
    else
      recommendations
    end
    
    # Check async potential
    recommendations = if analysis.async_potential.can_be_async > 0 do
      ["Consider enabling async for #{analysis.async_potential.can_be_async} safe test files" | recommendations]
    else
      recommendations
    end
    
    # Check resource usage
    recommendations = if analysis.resource_usage.high_resource_files > 2 do
      ["Consider resource pooling for #{analysis.resource_usage.high_resource_files} resource-intensive files" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  # Private functions

  defp count_test_files do
    Path.wildcard("test/**/*_test.exs") |> length()
  end

  defp analyze_migration_status do
    all_files = Path.wildcard("test/**/*_test.exs")
    migrated_files = all_files
    |> Enum.filter(fn file ->
      File.read!(file) |> String.contains?("Foundation.UnifiedTestFoundation")
    end)
    
    high_risk_files = all_files
    |> Enum.filter(&is_high_risk_file?/1)
    
    unmigrated_high_risk = high_risk_files
    |> Enum.reject(fn file ->
      File.read!(file) |> String.contains?("Foundation.UnifiedTestFoundation")
    end)
    
    %{
      total_files: length(all_files),
      migrated_files: length(migrated_files),
      migration_percentage: (length(migrated_files) / length(all_files) * 100) |> Float.round(1),
      high_risk_files: length(high_risk_files),
      unmigrated_high_risk: length(unmigrated_high_risk)
    }
  end

  defp analyze_resource_usage do
    test_files = Path.wildcard("test/**/*_test.exs")
    
    high_resource_files = test_files
    |> Enum.filter(&is_high_resource_file?/1)
    
    concurrent_unsafe_files = test_files
    |> Enum.filter(&is_concurrent_unsafe?/1)
    
    %{
      total_files: length(test_files),
      high_resource_files: length(high_resource_files),
      concurrent_unsafe_files: length(concurrent_unsafe_files),
      resource_efficiency: calculate_resource_efficiency(test_files)
    }
  end

  defp analyze_async_potential do
    test_files = Path.wildcard("test/**/*_test.exs")
    
    async_files = test_files
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, "async: true") or 
      (String.contains?(content, "UnifiedTestFoundation") and not String.contains?(content, "async: false"))
    end)
    
    can_be_async = test_files
    |> Enum.filter(&can_be_made_async?/1)
    |> Enum.reject(fn file ->
      File.read!(file) |> String.contains?("async: true")
    end)
    
    %{
      total_files: length(test_files),
      async_files: length(async_files),
      can_be_async: length(can_be_async),
      async_percentage: (length(async_files) / length(test_files) * 100) |> Float.round(1)
    }
  end

  defp analyze_contamination_risks do
    test_files = Path.wildcard("test/**/*_test.exs")
    
    telemetry_files = test_files
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, ":telemetry") or String.contains?(content, "telemetry")
    end)
    
    process_spawning_files = test_files
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, "spawn") or String.contains?(content, "start_link")
    end)
    
    %{
      total_files: length(test_files),
      telemetry_files: length(telemetry_files),
      process_spawning_files: length(process_spawning_files),
      contamination_risk_score: calculate_contamination_risk(test_files)
    }
  end

  defp is_high_risk_file?(file) do
    content = File.read!(file)
    String.contains?(content, "async: false") or
    String.contains?(content, ":meck") or
    String.contains?(content, "GenServer.start_link") or
    String.contains?(content, "Application.") or
    String.contains?(content, "Process.register")
  end

  defp is_high_resource_file?(file) do
    content = File.read!(file)
    String.contains?(content, "ResourceManager") or
    String.contains?(content, "CircuitBreaker") or
    String.contains?(content, "Agent") or
    String.contains?(content, "Supervisor") or
    String.contains?(content, ":ets.new")
  end

  defp is_concurrent_unsafe?(file) do
    content = File.read!(file)
    String.contains?(content, "async: false") or
    String.contains?(content, "@moduletag :serial") or
    String.contains?(content, "Process.register") or
    String.contains?(content, "Application.put_env")
  end

  defp can_be_made_async?(file) do
    content = File.read!(file)
    not String.contains?(content, "async: false") and
    not String.contains?(content, "Process.register") and
    not String.contains?(content, "Application.") and
    not String.contains?(content, ":meck") and
    not String.contains?(content, "@moduletag :serial")
  end

  defp calculate_resource_efficiency(files) do
    total_files = length(files)
    efficient_files = files
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, "UnifiedTestFoundation") or
      String.contains?(content, "async: true")
    end)
    
    (length(efficient_files) / total_files * 100) |> Float.round(1)
  end

  defp calculate_contamination_risk(files) do
    total_files = length(files)
    risky_files = files
    |> Enum.filter(&is_high_risk_file?/1)
    
    risk_score = length(risky_files) / total_files * 100
    Float.round(risk_score, 1)
  end

  defp categorize_test_file(file) do
    content = File.read!(file)
    
    category = cond do
      String.contains?(content, "UnifiedTestFoundation") -> :unified
      String.contains?(content, "async: false") -> :sync_required
      String.contains?(content, "ResourceManager") -> :resource_intensive
      String.contains?(content, ":telemetry") -> :telemetry_dependent
      String.contains?(content, "Agent") -> :agent_lifecycle
      String.contains?(content, "Supervisor") -> :supervisor_dependent
      true -> :standard
    end
    
    %{
      file: file,
      category: category,
      content_size: byte_size(content),
      estimated_runtime: estimate_runtime(content)
    }
  end

  defp sort_by_resource_requirements(categorized_files) do
    # Sort to minimize resource conflicts
    # 1. Standard tests first (can run async)
    # 2. Unified tests (isolated)
    # 3. Resource intensive tests (batched)
    # 4. Sync required tests last (serial)
    
    priority_order = [
      :standard,
      :unified,
      :telemetry_dependent,
      :agent_lifecycle,
      :resource_intensive,
      :supervisor_dependent,
      :sync_required
    ]
    
    Enum.sort_by(categorized_files, fn %{category: category} ->
      Enum.find_index(priority_order, &(&1 == category)) || 999
    end)
  end

  defp optimize_async_grouping(sorted_files) do
    # Group files that can safely run in parallel
    {async_files, sync_files} = Enum.split_with(sorted_files, fn %{category: category} ->
      category in [:standard, :unified, :telemetry_dependent]
    end)
    
    %{
      async_batch: async_files,
      sync_batch: sync_files,
      optimization_applied: true
    }
  end

  defp estimate_runtime(content) do
    # Simple heuristic based on content patterns
    base_time = 100  # 100ms base
    
    multipliers = [
      {~r/Agent/, 2.0},
      {~r/Supervisor/, 1.5},
      {~r/ResourceManager/, 3.0},
      {~r/CircuitBreaker/, 2.5},
      {~r/:telemetry/, 1.3},
      {~r/spawn/, 1.2},
      {~r/async: false/, 2.0}
    ]
    
    final_multiplier = multipliers
    |> Enum.reduce(1.0, fn {pattern, multiplier}, acc ->
      if Regex.match?(pattern, content), do: acc * multiplier, else: acc
    end)
    
    round(base_time * final_multiplier)
  end
end