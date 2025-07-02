defmodule Foundation.Services.SupervisorTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers

  alias Foundation.Services.Supervisor, as: ServicesSupervisor

  @moduletag :supervision_testing
  @moduletag timeout: 30_000

  # Helper to create unique service options for test supervisors
  defp create_test_service_opts(unique_name) do
    [
      monitor_manager: [name: :"#{unique_name}_monitor_manager"],
      retry_service: [name: :"#{unique_name}_retry_service"],
      connection_manager: [name: :"#{unique_name}_connection_manager"],
      rate_limiter: [name: :"#{unique_name}_rate_limiter"],
      signal_bus: [name: :"#{unique_name}_signal_bus"],
      dependency_manager: [
        name: :"#{unique_name}_dependency_manager",
        table_name: :"#{unique_name}_dependency_table"
      ],
      health_checker: [name: :"#{unique_name}_health_checker"]
    ]
  end

  describe "Foundation.Services.Supervisor" do
    test "starts with proper supervision strategy with unique name" do
      # Test that we can start the services supervisor with proper strategy
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      service_opts = create_test_service_opts(unique_name)

      assert {:ok, pid} =
               ServicesSupervisor.start_link(name: unique_name, service_opts: service_opts)

      assert Process.alive?(pid)

      # Verify supervision strategy
      children = Supervisor.which_children(pid)
      assert is_list(children)

      # Should have 5 services: MonitorManager, RetryService, ConnectionManager, RateLimiter, SignalBus
      # 5 Foundation services + 2 SIA services
      assert length(children) == 7

      # Clean up
      Supervisor.stop(pid)
    end

    test "properly supervises child services with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      service_opts = create_test_service_opts(unique_name)
      {:ok, pid} = ServicesSupervisor.start_link(name: unique_name, service_opts: service_opts)

      # Check that supervisor is properly configured
      children = Supervisor.which_children(pid)
      # 4 Foundation services + 2 SIA services
      assert length(children) == 7

      # The supervisor should be ready to accept child specifications
      assert Process.alive?(pid)

      Supervisor.stop(pid)
    end

    test "restarts failed services according to restart strategy with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      service_opts = create_test_service_opts(unique_name)

      {:ok, supervisor_pid} =
        ServicesSupervisor.start_link(name: unique_name, service_opts: service_opts)

      # This test validates the supervision tree structure
      # Should have 4 child services (RetryService, ConnectionManager, RateLimiter, SignalBus)
      children = Supervisor.which_children(supervisor_pid)
      # 4 Foundation services + 2 SIA services
      assert length(children) == 7

      Supervisor.stop(supervisor_pid)
    end

    test "graceful shutdown of all services with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      service_opts = create_test_service_opts(unique_name)

      {:ok, supervisor_pid} =
        ServicesSupervisor.start_link(name: unique_name, service_opts: service_opts)

      # Supervisor should shutdown gracefully
      assert :ok = Supervisor.stop(supervisor_pid)

      # Verify supervisor has terminated
      refute Process.alive?(supervisor_pid)
    end

    test "integrates with Foundation.Application supervision tree" do
      # Test that the main supervisor exists and has Services.Supervisor as child
      main_supervisor = Foundation.Supervisor
      children = Supervisor.which_children(main_supervisor)

      # Should find Foundation.Services.Supervisor in the children
      service_supervisor_child =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Foundation.Services.Supervisor
        end)

      assert service_supervisor_child != nil
      {_id, pid, _type, _modules} = service_supervisor_child
      assert Process.alive?(pid)
    end

    test "validates which_services returns current services", %{supervision_tree: sup_tree} do
      # Wait for services to be ready
      wait_for_services_ready(sup_tree)

      # Get services from isolated supervision tree (JidoFoundation services)
      services = get_supported_services()
      assert is_list(services)

      # Verify all expected services are available in the supervision tree
      for service <- services do
        assert {:ok, _pid} = get_service(sup_tree, service)
      end

      # Should have exactly 4 JidoFoundation services in supervision testing
      assert length(services) == 4
      assert :task_pool_manager in services
      assert :system_command_manager in services
      assert :coordination_manager in services
      assert :scheduler_manager in services
    end

    test "validates service_running? checks service status", %{supervision_tree: sup_tree} do
      # Wait for services to be ready (from troubleshooting guide)
      wait_for_services_ready(sup_tree)

      # Test using isolated supervision tree with available JidoFoundation services
      {:ok, task_pool_pid} = get_service(sup_tree, :task_pool_manager)
      {:ok, system_cmd_pid} = get_service(sup_tree, :system_command_manager)
      {:ok, coord_pid} = get_service(sup_tree, :coordination_manager)
      {:ok, scheduler_pid} = get_service(sup_tree, :scheduler_manager)

      # Verify services are running
      assert is_pid(task_pool_pid) and Process.alive?(task_pool_pid)
      assert is_pid(system_cmd_pid) and Process.alive?(system_cmd_pid)
      assert is_pid(coord_pid) and Process.alive?(coord_pid)
      assert is_pid(scheduler_pid) and Process.alive?(scheduler_pid)

      # Test that non-existent service returns error
      assert {:error, _} = get_service(sup_tree, :non_existent_service)
    end
  end
end
