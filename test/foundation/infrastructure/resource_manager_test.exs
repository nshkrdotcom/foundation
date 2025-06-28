defmodule Foundation.Infrastructure.ResourceManagerTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.Infrastructure.ResourceManager
  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    namespace = {:test, make_ref()}
    
    # Start ResourceManager with test configuration
    {:ok, _pid} = ResourceManager.start_link([
      monitoring_interval: 100,  # Fast monitoring for testing
      system_thresholds: %{
        memory: %{warning: 0.8, critical: 0.9},
        cpu: %{warning: 0.7, critical: 0.85},
        storage: %{warning: 0.9, critical: 0.95}
      },
      namespace: namespace
    ])

    on_exit(fn ->
      try do
        ResourceManager.clear_all_agents()
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace}
  end

  describe "agent resource registration" do
    test "registers agent with comprehensive resource requirements" do
      resource_limits = %{
        memory_limit: 2_000_000_000,      # 2GB
        cpu_limit: 2.0,                   # 2 cores
        storage_limit: 10_000_000_000,    # 10GB
        network_connections: 100,
        custom_resources: %{
          gpu_memory: 4_000_000_000,      # 4GB GPU memory
          model_cache: 1_000_000_000      # 1GB model cache
        }
      }

      resource_requirements = %{
        memory_weight: 0.8,    # High memory importance
        cpu_weight: 0.6,       # Medium CPU importance
        storage_weight: 0.3,   # Low storage importance
        burst_tolerance: 0.2   # 20% burst allowance
      }

      metadata = %{
        model_type: "transformer",
        expected_workload: "high_throughput_inference"
      }

      assert :ok = ResourceManager.register_agent(
        :ml_agent_1,
        resource_limits,
        resource_requirements,
        metadata
      )

      {:ok, agent_status} = ResourceManager.get_agent_resource_status(:ml_agent_1)

      assert agent_status.agent_id == :ml_agent_1
      assert agent_status.resource_limits.memory_limit == 2_000_000_000
      assert agent_status.resource_limits.cpu_limit == 2.0
      assert agent_status.resource_requirements.memory_weight == 0.8
      assert agent_status.metadata.model_type == "transformer"
    end

    test "validates resource limit parameters" do
      invalid_limits = %{
        memory_limit: -1000,      # Invalid negative value
        cpu_limit: "invalid",     # Invalid type
        storage_limit: 0          # Zero limit
      }

      assert {:error, reason} = ResourceManager.register_agent(
        :invalid_agent,
        invalid_limits
      )

      assert reason =~ "invalid_resource_limits"
    end

    test "prevents duplicate agent registration" do
      limits = %{memory_limit: 1_000_000_000}
      
      assert :ok = ResourceManager.register_agent(:duplicate_test, limits)
      
      assert {:error, :agent_already_registered} = ResourceManager.register_agent(
        :duplicate_test, 
        limits
      )
    end
  end

  describe "resource availability checking" do
    test "checks resource availability before allocation" do
      ResourceManager.register_agent(:test_agent, %{
        memory_limit: 1_000_000_000,  # 1GB
        cpu_limit: 1.0                # 1 core
      })

      # Check if 500MB memory is available
      result = ResourceManager.check_resource_availability(
        :test_agent,
        :memory,
        500_000_000
      )
      assert result == :ok

      # Check if 2GB memory is available (should fail)
      result = ResourceManager.check_resource_availability(
        :test_agent,
        :memory,
        2_000_000_000
      )
      assert {:error, reason} = result
      assert reason =~ "insufficient_resource"
    end

    test "considers current usage in availability checks" do
      ResourceManager.register_agent(:usage_test_agent, %{
        memory_limit: 1_000_000_000
      })

      # Allocate some memory first
      assert :ok = ResourceManager.allocate_resources(:usage_test_agent, %{
        memory: 600_000_000
      })

      # Check if additional 500MB is available (should fail - total would be 1.1GB)
      result = ResourceManager.check_resource_availability(
        :usage_test_agent,
        :memory,
        500_000_000
      )
      assert {:error, reason} = result
      assert reason =~ "insufficient_resource"

      # Check if 300MB is available (should succeed - total would be 900MB)
      result = ResourceManager.check_resource_availability(
        :usage_test_agent,
        :memory,
        300_000_000
      )
      assert result == :ok
    end
  end

  describe "resource allocation and release" do
    test "allocates and tracks resource usage" do
      ResourceManager.register_agent(:allocation_test, %{
        memory_limit: 2_000_000_000,
        cpu_limit: 2.0,
        storage_limit: 5_000_000_000
      })

      # Allocate multiple resource types
      allocation_request = %{
        memory: 800_000_000,     # 800MB
        cpu: 1.5,                # 1.5 cores
        storage: 2_000_000_000   # 2GB
      }

      assert :ok = ResourceManager.allocate_resources(:allocation_test, allocation_request)

      # Verify allocation is tracked
      {:ok, status} = ResourceManager.get_agent_resource_status(:allocation_test)
      
      assert status.current_usage.memory == 800_000_000
      assert status.current_usage.cpu == 1.5
      assert status.current_usage.storage == 2_000_000_000
      
      # Check utilization percentages
      assert status.utilization.memory == 0.4  # 800MB / 2GB
      assert status.utilization.cpu == 0.75    # 1.5 / 2.0
      assert status.utilization.storage == 0.4 # 2GB / 5GB
    end

    test "releases resources correctly" do
      ResourceManager.register_agent(:release_test, %{
        memory_limit: 1_000_000_000,
        cpu_limit: 2.0
      })

      # Allocate resources
      ResourceManager.allocate_resources(:release_test, %{
        memory: 600_000_000,
        cpu: 1.0
      })

      # Partially release resources
      assert :ok = ResourceManager.release_resources(:release_test, %{
        memory: 300_000_000
      })

      # Verify partial release
      {:ok, status} = ResourceManager.get_agent_resource_status(:release_test)
      assert status.current_usage.memory == 300_000_000
      assert status.current_usage.cpu == 1.0  # Unchanged

      # Release remaining resources
      assert :ok = ResourceManager.release_resources(:release_test, %{
        memory: 300_000_000,
        cpu: 1.0
      })

      # Verify complete release
      {:ok, status} = ResourceManager.get_agent_resource_status(:release_test)
      assert status.current_usage.memory == 0
      assert status.current_usage.cpu == 0
    end

    test "prevents over-release of resources" do
      ResourceManager.register_agent(:over_release_test, %{
        memory_limit: 1_000_000_000
      })

      # Allocate 500MB
      ResourceManager.allocate_resources(:over_release_test, %{memory: 500_000_000})

      # Try to release 800MB (more than allocated)
      result = ResourceManager.release_resources(:over_release_test, %{memory: 800_000_000})
      
      assert {:error, reason} = result
      assert reason =~ "insufficient_allocated"
    end
  end

  describe "burst and temporary allocations" do
    test "handles burst resource requests" do
      ResourceManager.register_agent(:burst_test, %{
        memory_limit: 1_000_000_000,
        cpu_limit: 1.0
      }, %{
        burst_tolerance: 0.5  # Allow 50% burst
      })

      # Normal allocation should work
      assert :ok = ResourceManager.allocate_resources(:burst_test, %{
        memory: 800_000_000
      })

      # Burst allocation should work (total 1.3GB > 1GB base limit)
      result = ResourceManager.allocate_burst_resources(:burst_test, %{
        memory: 500_000_000  # This puts us at 1.3GB total
      }, %{duration: 10_000})  # 10 second burst

      assert :ok = result

      {:ok, status} = ResourceManager.get_agent_resource_status(:burst_test)
      assert status.current_usage.memory == 1_300_000_000
      assert status.burst_active == true
      assert status.utilization.memory > 1.0  # Over 100% due to burst
    end

    test "automatically releases burst resources after timeout" do
      ResourceManager.register_agent(:burst_timeout_test, %{
        memory_limit: 1_000_000_000
      }, %{
        burst_tolerance: 0.3
      })

      # Allocate base resources
      ResourceManager.allocate_resources(:burst_timeout_test, %{memory: 700_000_000})

      # Allocate burst resources with short timeout
      ResourceManager.allocate_burst_resources(:burst_timeout_test, %{
        memory: 300_000_000
      }, %{duration: 200})  # 200ms burst

      # Verify burst is active
      {:ok, status} = ResourceManager.get_agent_resource_status(:burst_timeout_test)
      assert status.burst_active == true

      # Wait for burst timeout
      Process.sleep(300)

      # Verify burst was automatically released
      {:ok, status} = ResourceManager.get_agent_resource_status(:burst_timeout_test)
      assert status.burst_active == false
      assert status.current_usage.memory == 700_000_000  # Back to base allocation
    end
  end

  describe "system-wide resource monitoring" do
    test "provides system resource overview" do
      # Register multiple agents with different resource usage
      agents = [
        {:agent_1, %{memory_limit: 1_000_000_000, cpu_limit: 1.0}},
        {:agent_2, %{memory_limit: 2_000_000_000, cpu_limit: 2.0}},
        {:agent_3, %{memory_limit: 500_000_000, cpu_limit: 0.5}}
      ]

      for {agent_id, limits} <- agents do
        ResourceManager.register_agent(agent_id, limits)
      end

      # Allocate resources to agents
      ResourceManager.allocate_resources(:agent_1, %{memory: 800_000_000, cpu: 0.8})
      ResourceManager.allocate_resources(:agent_2, %{memory: 1_500_000_000, cpu: 1.5})
      ResourceManager.allocate_resources(:agent_3, %{memory: 400_000_000, cpu: 0.4})

      {:ok, system_status} = ResourceManager.get_system_resource_status()

      assert system_status.agent_count == 3
      assert system_status.total_limits.memory == 3_500_000_000  # Sum of all limits
      assert system_status.total_usage.memory == 2_700_000_000   # Sum of all usage
      assert system_status.system_utilization.memory ≈ 0.77     # 2.7GB / 3.5GB
      
      # Check individual agent summaries are included
      assert length(system_status.agent_summaries) == 3
    end

    test "detects system-wide resource pressure" do
      # Create scenario with high resource pressure
      ResourceManager.register_agent(:pressure_agent_1, %{memory_limit: 1_000_000_000})
      ResourceManager.register_agent(:pressure_agent_2, %{memory_limit: 1_000_000_000})

      # Allocate resources that put system under pressure
      ResourceManager.allocate_resources(:pressure_agent_1, %{memory: 950_000_000})  # 95%
      ResourceManager.allocate_resources(:pressure_agent_2, %{memory: 900_000_000})  # 90%

      {:ok, pressure_status} = ResourceManager.get_resource_pressure_status()

      assert pressure_status.overall_pressure == :high
      assert pressure_status.memory_pressure == :high
      assert length(pressure_status.high_pressure_agents) == 2
      assert pressure_status.recommendation =~ "reduce_allocation"
    end
  end

  describe "resource threshold monitoring and alerting" do
    test "triggers alerts when agents exceed thresholds" do
      ResourceManager.register_agent(:threshold_test, %{
        memory_limit: 1_000_000_000,
        cpu_limit: 1.0
      })

      # Set up alert handler
      alerts = Agent.start_link(fn -> [] end)
      
      ResourceManager.register_alert_handler(fn alert ->
        Agent.update(alerts, fn acc -> [alert | acc] end)
      end)

      # Allocate resources that exceed warning threshold (80%)
      ResourceManager.allocate_resources(:threshold_test, %{
        memory: 850_000_000,  # 85% - should trigger warning
        cpu: 0.9              # 90% - should trigger warning
      })

      # Allow monitoring cycle to detect threshold breach
      Process.sleep(150)

      captured_alerts = Agent.get(alerts, & &1)
      
      # Should have alerts for both memory and CPU
      memory_alert = Enum.find(captured_alerts, &(&1.resource_type == :memory))
      cpu_alert = Enum.find(captured_alerts, &(&1.resource_type == :cpu))
      
      assert memory_alert != nil
      assert memory_alert.agent_id == :threshold_test
      assert memory_alert.severity == :warning
      assert memory_alert.utilization >= 0.8

      assert cpu_alert != nil
      assert cpu_alert.agent_id == :threshold_test
      assert cpu_alert.severity == :warning
    end

    test "escalates to critical alerts at higher thresholds" do
      ResourceManager.register_agent(:critical_test, %{memory_limit: 1_000_000_000})

      alerts = Agent.start_link(fn -> [] end)
      ResourceManager.register_alert_handler(fn alert ->
        Agent.update(alerts, fn acc -> [alert | acc] end)
      end)

      # Allocate resources that exceed critical threshold (90%)
      ResourceManager.allocate_resources(:critical_test, %{memory: 950_000_000})  # 95%

      Process.sleep(150)

      captured_alerts = Agent.get(alerts, & &1)
      critical_alert = Enum.find(captured_alerts, &(&1.severity == :critical))
      
      assert critical_alert != nil
      assert critical_alert.agent_id == :critical_test
      assert critical_alert.utilization >= 0.9
    end
  end

  describe "resource optimization and recommendations" do
    test "provides resource optimization recommendations" do
      # Create agents with suboptimal resource allocation
      ResourceManager.register_agent(:underutilized, %{
        memory_limit: 2_000_000_000,
        cpu_limit: 2.0
      })
      
      ResourceManager.register_agent(:overutilized, %{
        memory_limit: 500_000_000,
        cpu_limit: 0.5
      })

      # Simulate usage patterns
      ResourceManager.allocate_resources(:underutilized, %{
        memory: 200_000_000,  # 10% utilization
        cpu: 0.2
      })
      
      ResourceManager.allocate_resources(:overutilized, %{
        memory: 480_000_000,  # 96% utilization
        cpu: 0.49
      })

      {:ok, recommendations} = ResourceManager.get_optimization_recommendations()

      # Should recommend downsizing underutilized agent
      underutil_rec = Enum.find(recommendations, &(&1.agent_id == :underutilized))
      assert underutil_rec.recommendation_type == :downsize
      assert underutil_rec.suggested_memory_limit < 2_000_000_000

      # Should recommend upsizing overutilized agent
      overutil_rec = Enum.find(recommendations, &(&1.agent_id == :overutilized))
      assert overutil_rec.recommendation_type == :upsize
      assert overutil_rec.suggested_memory_limit > 500_000_000
    end
  end

  property "resource allocations are consistent under concurrent operations" do
    check all(
      allocation_count <- integer(1..20),
      allocation_amounts <- list_of(integer(1_000_000..100_000_000), length: allocation_count)
    ) do
      agent_id = :property_test_agent
      total_limit = 2_000_000_000  # 2GB limit
      
      ResourceManager.register_agent(agent_id, %{memory_limit: total_limit})

      # Perform concurrent allocations
      tasks = allocation_amounts
      |> Enum.with_index()
      |> Enum.map(fn {amount, index} ->
        Task.async(fn ->
          ResourceManager.allocate_resources(agent_id, %{memory: amount})
        end)
      end)

      results = Task.await_many(tasks, 5000)

      # Get final status
      {:ok, final_status} = ResourceManager.get_agent_resource_status(agent_id)

      # Verify resource accounting consistency
      successful_allocations = Enum.count(results, &(&1 == :ok))
      
      # Should not exceed the agent's memory limit
      assert final_status.current_usage.memory <= total_limit
      
      # Should have some successful allocations if amounts are reasonable
      if Enum.sum(allocation_amounts) <= total_limit do
        assert successful_allocations > 0
      end

      # Cleanup
      ResourceManager.unregister_agent(agent_id)
    end
  end

  describe "error handling and edge cases" do
    test "handles agent process termination gracefully" do
      ResourceManager.register_agent(:termination_test, %{memory_limit: 1_000_000_000})
      
      # Allocate some resources
      ResourceManager.allocate_resources(:termination_test, %{memory: 500_000_000})

      # Simulate agent termination by unregistering
      ResourceManager.unregister_agent(:termination_test)

      # Verify resources are cleaned up
      result = ResourceManager.get_agent_resource_status(:termination_test)
      assert {:error, :agent_not_found} = result

      # System status should not include terminated agent
      {:ok, system_status} = ResourceManager.get_system_resource_status()
      agent_ids = Enum.map(system_status.agent_summaries, & &1.agent_id)
      assert :termination_test not in agent_ids
    end

    test "handles invalid resource operations gracefully" do
      ResourceManager.register_agent(:invalid_ops_test, %{memory_limit: 1_000_000_000})

      # Test allocation with invalid resource type
      result = ResourceManager.allocate_resources(:invalid_ops_test, %{
        invalid_resource: 100_000_000
      })
      assert {:error, reason} = result
      assert reason =~ "unsupported_resource_type"

      # Test allocation with invalid amount
      result = ResourceManager.allocate_resources(:invalid_ops_test, %{
        memory: -100_000_000  # Negative amount
      })
      assert {:error, reason} = result
      assert reason =~ "invalid_amount"
    end

    test "handles concurrent access to same agent resources" do
      ResourceManager.register_agent(:concurrent_test, %{memory_limit: 1_000_000_000})

      # Launch many concurrent allocation attempts
      tasks = for _i <- 1..50 do
        Task.async(fn ->
          ResourceManager.allocate_resources(:concurrent_test, %{memory: 100_000_000})
        end)
      end

      results = Task.await_many(tasks, 5000)

      # Should have some successes and some failures due to limits
      successes = Enum.count(results, &(&1 == :ok))
      failures = Enum.count(results, &match?({:error, _}, &1))

      assert successes + failures == 50
      assert successes <= 10  # Can't allocate more than 1GB / 100MB = 10 times

      # Final state should be consistent
      {:ok, status} = ResourceManager.get_agent_resource_status(:concurrent_test)
      assert status.current_usage.memory == successes * 100_000_000
    end
  end

  describe "integration with agent health and coordination" do
    test "adjusts resource management based on agent health", %{namespace: namespace} do
      # Register agent in ProcessRegistry with health info
      pid = spawn(fn -> Process.sleep(2000) end)
      agent_metadata = %AgentInfo{
        id: :health_integrated_agent,
        type: :ml_agent,
        capabilities: [:inference],
        health: :healthy,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }

      ProcessRegistry.register_agent(namespace, :health_integrated_agent, pid, agent_metadata)

      # Register same agent in ResourceManager
      ResourceManager.register_agent(:health_integrated_agent, %{
        memory_limit: 1_000_000_000
      })

      # Healthy agent should get normal resource allocation
      result = ResourceManager.allocate_resources(:health_integrated_agent, %{
        memory: 800_000_000
      })
      assert :ok = result

      # Update agent health to degraded
      degraded_metadata = %AgentInfo{
        agent_metadata | 
        health: :degraded,
        resource_usage: %{memory: 0.9, cpu: 0.8}
      }
      ProcessRegistry.update_agent_metadata(namespace, :health_integrated_agent, degraded_metadata)

      # ResourceManager should detect degraded health and be more conservative
      {:ok, status} = ResourceManager.get_agent_resource_status(:health_integrated_agent)
      assert status.health_adjusted_limits != nil
      
      # Should recommend reducing allocation for degraded agent
      {:ok, recommendations} = ResourceManager.get_optimization_recommendations()
      health_rec = Enum.find(recommendations, &(&1.agent_id == :health_integrated_agent))
      assert health_rec.reason =~ "health_degraded"
    end
  end
end