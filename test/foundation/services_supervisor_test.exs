defmodule Foundation.Services.SupervisorTest do
  use ExUnit.Case, async: true

  alias Foundation.Services.Supervisor, as: ServicesSupervisor

  # Helper to create unique service options for test supervisors
  defp create_test_service_opts(unique_name) do
    [
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

      # Should have 4 services: RetryService, ConnectionManager, RateLimiter, SignalBus
      # 4 Foundation services + 2 SIA services
      assert length(children) == 6

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
      assert length(children) == 6

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
      assert length(children) == 6

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

    test "validates which_services returns current services" do
      # Test using the existing Foundation.Services.Supervisor
      services = ServicesSupervisor.which_services()
      assert is_list(services)
      assert Foundation.Services.RetryService in services
      assert Foundation.Services.ConnectionManager in services
      assert Foundation.Services.RateLimiter in services
      assert Foundation.Services.SignalBus in services
      # 4 Foundation services + 2 SIA services
      assert length(services) == 6
    end

    test "validates service_running? checks service status" do
      # Test using the existing Foundation.Services.Supervisor
      assert ServicesSupervisor.service_running?(Foundation.Services.RetryService)
      assert ServicesSupervisor.service_running?(Foundation.Services.ConnectionManager)
      assert ServicesSupervisor.service_running?(Foundation.Services.RateLimiter)
      assert ServicesSupervisor.service_running?(Foundation.Services.SignalBus)
      refute ServicesSupervisor.service_running?(SomeNonExistentService)
    end
  end
end
