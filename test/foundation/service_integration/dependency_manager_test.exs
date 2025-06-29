defmodule Foundation.ServiceIntegration.DependencyManagerTest do
  use ExUnit.Case, async: false
  
  alias Foundation.ServiceIntegration.DependencyManager

  describe "DependencyManager" do
    test "starts and stops cleanly" do
      {:ok, pid} = DependencyManager.start_link(name: :test_dependency_manager)
      assert Process.alive?(pid)
      
      GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "registers and retrieves service dependencies" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_register)
      
      # Register a service with dependencies
      :ok = GenServer.call(:test_dep_mgr_register, 
        {:register_service, TestService, [Foundation.Services.RetryService]}
      )
      
      # Get all dependencies
      deps = GenServer.call(:test_dep_mgr_register, :get_all_dependencies)
      
      assert Map.has_key?(deps, TestService)
      assert deps[TestService] == [Foundation.Services.RetryService]
      
      GenServer.stop(:test_dep_mgr_register)
    end

    test "validates dependencies and detects missing services" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_validate)
      
      # Register a service with non-existent dependency
      :ok = GenServer.call(:test_dep_mgr_validate,
        {:register_service, TestService, [NonExistentService]}
      )
      
      # Validate should detect missing service
      result = GenServer.call(:test_dep_mgr_validate, :validate_dependencies)
      
      assert {:error, {:missing_services, missing}} = result
      assert NonExistentService in missing
      
      GenServer.stop(:test_dep_mgr_validate)
    end

    test "detects circular dependencies" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_circular)
      
      # Create circular dependency: A -> B -> A
      :ok = GenServer.call(:test_dep_mgr_circular,
        {:register_service, ServiceA, [ServiceB]}
      )
      :ok = GenServer.call(:test_dep_mgr_circular,
        {:register_service, ServiceB, [ServiceA]}
      )
      
      # Validate should detect circular dependency
      result = GenServer.call(:test_dep_mgr_circular, :validate_dependencies)
      
      assert {:error, {:circular_dependencies, cycles}} = result
      assert length(cycles) > 0
      
      GenServer.stop(:test_dep_mgr_circular)
    end

    test "calculates correct startup order" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_order)
      
      # Register services with dependencies: A depends on B, B depends on C
      :ok = GenServer.call(:test_dep_mgr_order,
        {:register_service, ServiceA, [ServiceB]}
      )
      :ok = GenServer.call(:test_dep_mgr_order,
        {:register_service, ServiceB, [ServiceC]}
      )
      :ok = GenServer.call(:test_dep_mgr_order,
        {:register_service, ServiceC, []}
      )
      
      # Get startup order
      {:ok, order} = GenServer.call(:test_dep_mgr_order,
        {:get_startup_order, [ServiceA, ServiceB, ServiceC]}
      )
      
      # ServiceC should be first (no dependencies)
      # ServiceB should be second (depends on C)
      # ServiceA should be last (depends on B)
      assert order == [ServiceC, ServiceB, ServiceA]
      
      GenServer.stop(:test_dep_mgr_order)
    end

    test "handles empty dependency lists" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_empty)
      
      # Register service with no dependencies
      :ok = GenServer.call(:test_dep_mgr_empty,
        {:register_service, IndependentService, []}
      )
      
      # Should validate successfully
      result = GenServer.call(:test_dep_mgr_empty, :validate_dependencies)
      assert result == :ok
      
      # Should return service in startup order
      {:ok, order} = GenServer.call(:test_dep_mgr_empty,
        {:get_startup_order, [IndependentService]}
      )
      assert order == [IndependentService]
      
      GenServer.stop(:test_dep_mgr_empty)
    end

    test "unregisters services correctly" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_unregister)
      
      # Register then unregister a service
      :ok = GenServer.call(:test_dep_mgr_unregister,
        {:register_service, TempService, []}
      )
      
      deps_before = GenServer.call(:test_dep_mgr_unregister, :get_all_dependencies)
      assert Map.has_key?(deps_before, TempService)
      
      :ok = GenServer.call(:test_dep_mgr_unregister,
        {:unregister_service, TempService}
      )
      
      deps_after = GenServer.call(:test_dep_mgr_unregister, :get_all_dependencies)
      refute Map.has_key?(deps_after, TempService)
      
      GenServer.stop(:test_dep_mgr_unregister)
    end

    test "handles complex dependency graphs" do
      {:ok, _pid} = DependencyManager.start_link(name: :test_dep_mgr_complex)
      
      # Create a more complex dependency graph
      # A -> [B, C]
      # B -> [D]
      # C -> [D, E]
      # D -> []
      # E -> []
      :ok = GenServer.call(:test_dep_mgr_complex,
        {:register_service, ServiceA, [ServiceB, ServiceC]}
      )
      :ok = GenServer.call(:test_dep_mgr_complex,
        {:register_service, ServiceB, [ServiceD]}
      )
      :ok = GenServer.call(:test_dep_mgr_complex,
        {:register_service, ServiceC, [ServiceD, ServiceE]}
      )
      :ok = GenServer.call(:test_dep_mgr_complex,
        {:register_service, ServiceD, []}
      )
      :ok = GenServer.call(:test_dep_mgr_complex,
        {:register_service, ServiceE, []}
      )
      
      # Get startup order
      {:ok, order} = GenServer.call(:test_dep_mgr_complex,
        {:get_startup_order, [ServiceA, ServiceB, ServiceC, ServiceD, ServiceE]}
      )
      
      # D and E should come first (no dependencies)
      # B and C should come after D and E
      # A should come last
      assert ServiceD in order
      assert ServiceE in order
      
      a_index = Enum.find_index(order, &(&1 == ServiceA))
      b_index = Enum.find_index(order, &(&1 == ServiceB))
      c_index = Enum.find_index(order, &(&1 == ServiceC))
      d_index = Enum.find_index(order, &(&1 == ServiceD))
      e_index = Enum.find_index(order, &(&1 == ServiceE))
      
      # A should come after B and C
      assert a_index > b_index
      assert a_index > c_index
      
      # B should come after D
      assert b_index > d_index
      
      # C should come after D and E
      assert c_index > d_index
      assert c_index > e_index
      
      GenServer.stop(:test_dep_mgr_complex)
    end
  end
end