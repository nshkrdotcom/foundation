defmodule Foundation.TaskHelper do
  @moduledoc """
  Helper functions for spawning supervised tasks across Foundation.

  Provides consistent supervised task spawning with fallback to regular spawn
  in test environments where the TaskSupervisor might not be running.
  """

  require Logger

  @doc """
  Spawns a supervised task using Foundation.TaskSupervisor.

  Falls back to regular spawn if the supervisor is not available (test environments).
  
  ## Examples

      Foundation.TaskHelper.spawn_supervised(fn ->
        IO.puts("Hello from supervised task")
      end)
  """
  def spawn_supervised(fun) when is_function(fun, 0) do
    case Process.whereis(Foundation.TaskSupervisor) do
      nil ->
        # TaskSupervisor not running, fall back to spawn (test environment)
        spawn(fun)
        
      _pid ->
        # TaskSupervisor is running, use proper supervision
        case Task.Supervisor.start_child(Foundation.TaskSupervisor, fun) do
          {:ok, pid} -> 
            pid
          {:error, reason} ->
            Logger.warning("Task.Supervisor.start_child failed: #{inspect(reason)}, falling back to spawn")
            spawn(fun)
        end
    end
  end

  @doc """
  Spawns a supervised task with error handling.

  Wraps the function in a try-rescue block and logs any errors.
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
end