defmodule Foundation.TaskHelper do
  @moduledoc """
  Helper functions for spawning supervised tasks across Foundation.

  Ensures all tasks are properly supervised, even in test environments.
  No unsupervised processes are allowed to maintain OTP principles.
  """

  require Logger

  @doc """
  Spawns a supervised task using Foundation.TaskSupervisor.

  Returns {:ok, pid} on success or {:error, reason} on failure.
  Never creates unsupervised processes.

  ## Examples

      {:ok, pid} = Foundation.TaskHelper.spawn_supervised(fn ->
        IO.puts("Hello from supervised task")
      end)
  """
  def spawn_supervised(fun) when is_function(fun, 0) do
    case Process.whereis(Foundation.TaskSupervisor) do
      nil ->
        # In test environment, use a global test supervisor
        # First try to find or start the test supervisor
        test_supervisor_name = Foundation.TestTaskSupervisor

        case Process.whereis(test_supervisor_name) do
          nil ->
            # Start a test supervisor if not already running
            case Task.Supervisor.start_link(name: test_supervisor_name) do
              {:ok, _pid} ->
                Task.Supervisor.start_child(test_supervisor_name, fun)

              {:error, {:already_started, _pid}} ->
                Task.Supervisor.start_child(test_supervisor_name, fun)

              error ->
                error
            end

          _pid ->
            # Test supervisor already running
            Task.Supervisor.start_child(test_supervisor_name, fun)
        end

      _pid ->
        # TaskSupervisor is running, use proper supervision
        case Task.Supervisor.start_child(Foundation.TaskSupervisor, fun) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, reason} = error ->
            Logger.error("Task.Supervisor.start_child failed: #{inspect(reason)}")
            error
        end
    end
  end

  @doc """
  Spawns a supervised task with error handling.

  Wraps the function in a try-rescue block and logs any errors.
  Returns {:ok, pid} on success or {:error, reason} on failure.
  """
  def spawn_supervised_safe(fun) when is_function(fun, 0) do
    spawn_supervised(fn ->
      try do
        fun.()
      rescue
        error ->
          Logger.error("Supervised task failed: #{Exception.message(error)}")
          Logger.debug("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      end
    end)
  end

  @doc """
  Spawns a supervised task and returns just the pid for backward compatibility.

  Raises on error. Use spawn_supervised/1 for safer error handling.
  """
  def spawn_supervised!(fun) when is_function(fun, 0) do
    case spawn_supervised(fun) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "Failed to spawn supervised task: #{inspect(reason)}"
    end
  end
end
