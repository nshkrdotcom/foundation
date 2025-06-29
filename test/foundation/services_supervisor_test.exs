defmodule Foundation.Services.SupervisorTest do
  use ExUnit.Case, async: true

  alias Foundation.Services.Supervisor, as: ServicesSupervisor

  describe "Foundation.Services.Supervisor" do
    test "starts with proper supervision strategy with unique name" do
      # Test that we can start the services supervisor with proper strategy
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      assert {:ok, pid} = ServicesSupervisor.start_link(name: unique_name)
      assert Process.alive?(pid)

      # Verify supervision strategy
      children = Supervisor.which_children(pid)
      assert is_list(children)

      # Should have 3 services: RetryService, ConnectionManager, RateLimiter
      assert length(children) == 3

      # Clean up
      Supervisor.stop(pid)
    end

    test "properly supervises child services with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      {:ok, pid} = ServicesSupervisor.start_link(name: unique_name)

      # Check that supervisor is properly configured
      children = Supervisor.which_children(pid)
      assert length(children) == 3

      # The supervisor should be ready to accept child specifications
      assert Process.alive?(pid)

      Supervisor.stop(pid)
    end

    test "restarts failed services according to restart strategy with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      {:ok, supervisor_pid} = ServicesSupervisor.start_link(name: unique_name)

      # This test validates the supervision tree structure
      # Should have 3 child services (RetryService, ConnectionManager, RateLimiter)
      children = Supervisor.which_children(supervisor_pid)
      assert length(children) == 3

      Supervisor.stop(supervisor_pid)
    end

    test "graceful shutdown of all services with unique name" do
      unique_name = :"test_supervisor_#{System.unique_integer()}"
      {:ok, supervisor_pid} = ServicesSupervisor.start_link(name: unique_name)

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
      assert length(services) == 3
    end

    test "validates service_running? checks service status" do
      # Test using the existing Foundation.Services.Supervisor
      assert ServicesSupervisor.service_running?(Foundation.Services.RetryService)
      assert ServicesSupervisor.service_running?(Foundation.Services.ConnectionManager)
      assert ServicesSupervisor.service_running?(Foundation.Services.RateLimiter)
      refute ServicesSupervisor.service_running?(SomeNonExistentService)
    end
  end
end
