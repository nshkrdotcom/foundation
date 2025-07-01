defmodule Foundation.TestSupervisorHelper do
  @moduledoc """
  Test-specific supervisor helpers for Foundation tests.

  This module provides test-only functionality for creating isolated
  supervisors and supervised tasks in test environments.
  """

  @doc """
  Sets up a test-specific task supervisor.

  This ensures tasks in tests are properly supervised.
  """
  def setup_test_task_supervisor do
    case Process.whereis(Foundation.TestTaskSupervisor) do
      nil ->
        # Start a test supervisor if not already running
        case Task.Supervisor.start_link(name: Foundation.TestTaskSupervisor) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Creates a test-specific service supervisor with isolated services.

  Useful for testing service interactions without affecting global state.

  ## Example

      {:ok, supervisor} = TestSupervisorHelper.create_test_service_supervisor()
      # Services are now available with test-specific names
  """
  def create_test_service_supervisor(name \\ nil) do
    supervisor_name = name || :"TestServiceSupervisor_#{System.unique_integer()}"

    # Create service options with unique names to avoid conflicts
    service_opts = [
      retry_service: [name: :"#{supervisor_name}_retry_service"],
      connection_manager: [name: :"#{supervisor_name}_connection_manager"],
      rate_limiter: [name: :"#{supervisor_name}_rate_limiter"],
      signal_bus: [name: :"#{supervisor_name}_signal_bus"],
      dependency_manager: [
        name: :"#{supervisor_name}_dependency_manager",
        table_name: :"#{supervisor_name}_dependency_table"
      ],
      health_checker: [name: :"#{supervisor_name}_health_checker"]
    ]

    Foundation.Services.Supervisor.start_link(
      name: supervisor_name,
      service_opts: service_opts
    )
  end

  @doc """
  Spawn a task using the test task supervisor.

  This ensures tasks in tests are properly supervised.
  """
  def spawn_test_task(fun) when is_function(fun, 0) do
    case setup_test_task_supervisor() do
      {:ok, _} ->
        Task.Supervisor.start_child(Foundation.TestTaskSupervisor, fun)

      error ->
        error
    end
  end

  @doc """
  Use Foundation.TaskHelper with proper test supervision.

  This sets up test supervision before delegating to TaskHelper.
  """
  def spawn_supervised(fun) when is_function(fun, 0) do
    # Ensure test task supervisor is running
    case setup_test_task_supervisor() do
      {:ok, _} ->
        # Now Foundation.TaskSupervisor exists (as an alias to test supervisor)
        # so TaskHelper will work
        Process.register(Process.whereis(Foundation.TestTaskSupervisor), Foundation.TaskSupervisor)
        Foundation.TaskHelper.spawn_supervised(fun)

      error ->
        error
    end
  end
end
