if Code.ensure_loaded?(Credo.Check) do
  defmodule Foundation.CredoChecks.NoRawSend do
    @moduledoc """
    Custom Credo check to ban raw send/2 usage.

    Raw send/2 provides no delivery guarantees and can lead to silent message loss.
    Use GenServer.call/cast or monitored sends for critical communication.
    """

    use Credo.Check,
      base_priority: :high,
      category: :warning,
      explanations: [
        check: """
        Raw send/2 provides no delivery guarantees. If the target process is dead or busy,
        messages are silently dropped. This can lead to data loss and hard-to-debug issues.

        Instead, use:
        - GenServer.call/3 for synchronous communication with timeouts
        - GenServer.cast/2 for async communication to GenServers
        - Task.Supervisor.async_nolink + Task.await for monitored async work
        - Process.monitor + send for cases where you need to track delivery

        ## Examples

        BAD:
            send(pid, {:work, data})
            
        GOOD:
            GenServer.call(pid, {:work, data})
            GenServer.cast(pid, {:work, data})
        """
      ]

    @doc false
    def run(source_file, params) do
      issue_meta = Credo.IssueMeta.for(source_file, params)

      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end

    defp traverse({:send, meta, [_target, _message]} = ast, issues, issue_meta) do
      # Allow sends within GenServer/Agent/Task modules as they're managed
      unless in_allowed_context?(ast, issue_meta) do
        issue = %Credo.Issue{
          category: :warning,
          check: __MODULE__,
          column: meta[:column],
          filename: issue_meta.filename,
          line_no: meta[:line] || 1,
          message: "Avoid raw send/2. Use GenServer.call/cast or monitored communication instead.",
          priority: :high,
          scope: :send,
          trigger: :send
        }

        {ast, [issue | issues]}
      else
        {ast, issues}
      end
    end

    defp traverse(ast, issues, _issue_meta) do
      {ast, issues}
    end

    defp in_allowed_context?(_ast, %{filename: filename}) do
      # Allow raw sends in specific system modules where they're properly managed
      allowed_modules = [
        "gen_server.ex",
        "gen_statem.ex",
        "supervisor.ex",
        "task.ex",
        "agent.ex",
        "registry.ex"
      ]

      Enum.any?(allowed_modules, &String.ends_with?(filename, &1))
    end
  end
else
  # Credo not available, define empty module
  defmodule Foundation.CredoChecks.NoRawSend do
    @moduledoc """
    Custom Credo check to ban raw send/2 usage.

    Note: Credo is not available, so this check is disabled.
    """
  end
end
