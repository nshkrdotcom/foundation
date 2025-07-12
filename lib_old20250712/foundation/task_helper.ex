defmodule Foundation.TaskHelper do
  @moduledoc """
  Helper functions for spawning supervised tasks across Foundation.

  Ensures all tasks are properly supervised to maintain OTP principles.

  ## Production Usage

  In production, this module uses Foundation.TaskSupervisor which is
  started by Foundation.Application.

  ## Test Usage

  In tests, you must ensure Foundation.TaskSupervisor is available by either:

  1. Starting Foundation.Application in your test:
     
         setup do
           {:ok, _} = Application.ensure_all_started(:foundation)
           :ok
         end
         
  2. Using test helpers to set up isolated supervision:

         # In test/test_helper.exs or test setup
         Foundation.TestSupervisorHelper.setup_test_task_supervisor()

  Never spawn unsupervised processes.
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
      
  ## Error Handling

  If Foundation.TaskSupervisor is not running (e.g., in isolated tests),
  this function returns an error. Tests should set up proper supervision
  using test helpers or start Foundation.Application.
  """
  def spawn_supervised(fun) when is_function(fun, 0) do
    case Process.whereis(Foundation.TaskSupervisor) do
      nil ->
        # TaskSupervisor not running - this is an error condition
        # Tests should properly set up supervision before using this function
        Logger.error(
          "Foundation.TaskSupervisor not running. " <>
            "Ensure Foundation.Application is started or use test helpers."
        )

        {:error, :task_supervisor_not_running}

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
