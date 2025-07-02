defmodule Foundation.MonitorMigration do
  @moduledoc """
  Helpers for migrating raw Process.monitor calls to MonitorManager.

  This module provides both macro helpers for automatic cleanup patterns
  and code analysis functions to identify and migrate existing Process.monitor
  usage throughout the codebase.

  ## Macro Helpers

  The `monitor_with_cleanup/3` macro provides automatic monitor cleanup:

      import Foundation.MonitorMigration
      
      monitor_with_cleanup(worker_pid, :worker_monitor) do
        # Do work that requires monitoring worker_pid
        GenServer.call(worker_pid, :get_status)
      end
      # Monitor is automatically cleaned up here

  ## GenServer Migration

  The `migrate_genserver_module/1` function helps migrate existing GenServer
  modules to use MonitorManager:

      # Analyze existing module
      {:ok, content} = File.read("lib/my_app/my_server.ex")
      migrated_content = MonitorMigration.migrate_genserver_module(content)
      File.write!("lib/my_app/my_server.ex", migrated_content)

  ## Code Analysis

  Several functions help identify Process.monitor usage:

      # Find all files with Process.monitor calls
      files = MonitorMigration.find_monitor_usage("lib/")
      
      # Analyze specific file
      issues = MonitorMigration.analyze_monitor_usage("lib/my_app/server.ex")
  """

  require Logger

  @doc """
  Macro that monitors a process and automatically cleans up the monitor
  when the block completes, even if an exception occurs.

  This is useful for temporary monitoring scenarios where you need to
  monitor a process for the duration of an operation.

  ## Examples

      import Foundation.MonitorMigration
      
      # Monitor with default tag
      result = monitor_with_cleanup(worker_pid) do
        GenServer.call(worker_pid, :heavy_operation, 30_000)
      end
      
      # Monitor with custom tag for debugging
      result = monitor_with_cleanup(worker_pid, :heavy_operation) do
        GenServer.call(worker_pid, :heavy_operation, 30_000)
      end
  """
  defmacro monitor_with_cleanup(pid, tag \\ :temporary, do: block) do
    quote do
      case Foundation.MonitorManager.monitor(unquote(pid), unquote(tag)) do
        {:ok, ref} ->
          try do
            unquote(block)
          after
            Foundation.MonitorManager.demonitor(ref)
          end

        {:error, reason} ->
          Logger.warning("Failed to create monitor for cleanup pattern",
            pid: inspect(unquote(pid)),
            tag: unquote(tag),
            reason: inspect(reason)
          )

          # Still execute the block even if monitoring failed
          unquote(block)
      end
    end
  end

  @doc """
  Migrates a GenServer module to use MonitorManager instead of raw Process.monitor.

  This function performs several transformations:
  1. Adds a `monitors` field to the state if using defstruct
  2. Replaces Process.monitor calls with MonitorManager.monitor
  3. Adds proper cleanup in terminate/2 callback
  4. Adds alias for Foundation.MonitorManager if needed

  ## Examples

      {:ok, content} = File.read("lib/my_server.ex")
      migrated = MonitorMigration.migrate_genserver_module(content)
      File.write!("lib/my_server.ex", migrated)
  """
  def migrate_genserver_module(module_code) when is_binary(module_code) do
    module_code
    |> add_monitor_manager_alias()
    |> add_monitor_tracking()
    |> replace_monitor_calls()
    |> add_terminate_cleanup()
    |> add_handle_info_cleanup()
  end

  @doc """
  Finds all files in a directory tree that contain Process.monitor calls.

  Returns a list of file paths that need to be reviewed for migration.

  ## Examples

      # Find all files with monitors in lib/
      files = MonitorMigration.find_monitor_usage("lib/")
      
      # Find in specific subdirectory
      files = MonitorMigration.find_monitor_usage("lib/my_app/")
  """
  def find_monitor_usage(directory) do
    Path.wildcard("#{directory}/**/*.ex")
    |> Enum.filter(fn file ->
      case File.read(file) do
        {:ok, content} -> String.contains?(content, "Process.monitor")
        {:error, _} -> false
      end
    end)
  end

  @doc """
  Analyzes monitor usage in a specific file and returns migration recommendations.

  Returns a list of issues found, each containing:
  - `:line` - Line number where issue was found
  - `:type` - Type of issue (`:raw_monitor`, `:missing_cleanup`, etc.)
  - `:message` - Human readable description
  - `:suggestion` - Suggested fix

  ## Examples

      issues = MonitorMigration.analyze_monitor_usage("lib/my_server.ex")
      Enum.each(issues, fn issue_item ->
        IO.puts("Line \#{issue_item.line}: \#{issue_item.message}")
      end)
  """
  def analyze_monitor_usage(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        analyze_content(content)

      {:error, reason} ->
        [
          %{
            line: 0,
            type: :file_error,
            message: "Could not read file: #{reason}",
            suggestion: "Check file permissions and path"
          }
        ]
    end
  end

  @doc """
  Generates a migration report for a directory tree.

  This function scans all .ex files in the given directory and generates
  a comprehensive report of monitor usage and migration needs.

  ## Examples

      report = MonitorMigration.generate_migration_report("lib/")
      IO.puts(report)
  """
  def generate_migration_report(directory) do
    files_with_monitors = find_monitor_usage(directory)
    total_files = length(Path.wildcard("#{directory}/**/*.ex"))

    issues_by_file =
      Enum.map(files_with_monitors, fn file ->
        {file, analyze_monitor_usage(file)}
      end)

    total_issues =
      issues_by_file
      |> Enum.map(fn {_file, issues} -> length(issues) end)
      |> Enum.sum()

    generate_report_text(directory, total_files, files_with_monitors, issues_by_file, total_issues)
  end

  # Private helper functions

  defp add_monitor_manager_alias(code) do
    if String.contains?(code, "Foundation.MonitorManager") do
      code
    else
      # Add alias after module declaration or after other aliases
      cond do
        # Has existing aliases - add after the last one
        String.contains?(code, "alias ") ->
          Regex.replace(
            ~r/(alias [^\n]+\n)(?!\s*alias)/,
            code,
            "\\1  alias Foundation.MonitorManager\n",
            global: false
          )

        # Has use GenServer - add alias after it
        String.contains?(code, "use GenServer") ->
          Regex.replace(
            ~r/(use GenServer\n)/,
            code,
            "\\1  alias Foundation.MonitorManager\n"
          )

        # Add after module declaration
        true ->
          Regex.replace(
            ~r/(defmodule .+ do\n)/,
            code,
            "\\1  alias Foundation.MonitorManager\n"
          )
      end
    end
  end

  defp add_monitor_tracking(code) do
    cond do
      # Has defstruct - add monitors field
      String.contains?(code, "defstruct") ->
        Regex.replace(
          ~r/defstruct\s+\[(.*?)\]/s,
          code,
          fn full, fields ->
            if String.contains?(full, "monitors:") do
              full
            else
              # Add monitors field
              "defstruct [#{fields}, monitors: %{}]"
            end
          end
        )

      # Has state initialization - suggest adding monitors
      String.contains?(code, "def init(") ->
        # Add comment suggesting monitors field
        Regex.replace(
          ~r/(def init\([^)]*\) do\n\s*.*?{:ok,\s*%{)/s,
          code,
          "\\1# TODO: Add monitors: %{} to state for MonitorManager integration\n    \\1"
        )

      true ->
        code
    end
  end

  defp replace_monitor_calls(code) do
    # Replace Process.monitor(pid) with MonitorManager.monitor pattern
    Regex.replace(
      ~r/Process\.monitor\(([^)]+)\)/,
      code,
      fn full, pid_expr ->
        # Determine appropriate tag based on context
        tag =
          if String.contains?(code, full) do
            # Extract module name for tag
            case Regex.run(~r/defmodule\s+([^\s]+)/, code) do
              [_, module_name] ->
                module_parts = String.split(module_name, ".")
                tag_name = module_parts |> List.last() |> Macro.underscore()
                ":#{tag_name}_monitor"

              nil ->
                ":monitor"
            end
          else
            ":monitor"
          end

        """
        case MonitorManager.monitor(#{String.trim(pid_expr)}, #{tag}) do
          {:ok, ref} -> 
            # TODO: Store ref in state.monitors for cleanup in terminate/2
            ref
          {:error, reason} ->
            Logger.warning("Failed to monitor process", 
              pid: inspect(#{String.trim(pid_expr)}), 
              reason: reason
            )
            # Fallback to raw monitor if MonitorManager unavailable
            Process.monitor(#{String.trim(pid_expr)})
        end\
        """
      end
    )
  end

  defp add_terminate_cleanup(code) do
    cond do
      # Already has terminate callback
      String.contains?(code, "def terminate(") ->
        # Add monitor cleanup to existing terminate
        Regex.replace(
          ~r/(def terminate\([^,]+,\s*([^)]+)\)\s*do\n)/,
          code,
          """
          \\1    # Clean up MonitorManager monitors
            Enum.each(Map.keys(\\2.monitors || %{}), fn ref ->
              MonitorManager.demonitor(ref)
            end)
            
          """
        )

      # No terminate callback - add one
      String.contains?(code, "use GenServer") ->
        # Find end of module and add terminate before it
        Regex.replace(
          ~r/(\n\s*# Private functions.*?\nend|\nend)$/s,
          code,
          "\n  @impl true\n  def terminate(_reason, state) do\n    # Clean up MonitorManager monitors\n    Enum.each(Map.keys(state.monitors || %{}), fn ref ->\n      MonitorManager.demonitor(ref)\n    end)\n    :ok\n  end\n\\1"
        )

      true ->
        code
    end
  end

  defp add_handle_info_cleanup(code) do
    # Add handle_info for DOWN messages if not present
    if String.contains?(code, "def handle_info({:DOWN") do
      code
    else
      # Add handle_info for DOWN message handling
      # Find the last occurrence of common patterns to insert before end
      terminate_pos =
        case :binary.match(code, "def terminate") do
          {pos, _} ->
            pos

          :nomatch ->
            case :binary.match(code, "@impl true") do
              {pos, _} ->
                pos

              :nomatch ->
                case :binary.match(code, "end") do
                  {pos, _} -> max(0, pos - 3)
                  :nomatch -> 0
                end
            end
        end

      if terminate_pos do
        {before, after_str} = String.split_at(code, terminate_pos)

        before <>
          "\n  @impl true\n  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do\n    # Remove from our monitor tracking\n    new_monitors = Map.delete(state.monitors || %{}, ref)\n    {:noreply, %{state | monitors: new_monitors}}\n  end\n\n  def handle_info(_msg, state) do\n    {:noreply, state}\n  end\n\n" <>
          after_str
      else
        code
      end
    end
  end

  defp analyze_content(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      analyze_line(line, line_num)
    end)
    |> add_structural_issues(content)
  end

  defp analyze_line(line, line_num) do
    issues = []

    # Check for raw Process.monitor calls
    issues =
      if String.contains?(line, "Process.monitor") do
        [
          %{
            line: line_num,
            type: :raw_monitor,
            message: "Raw Process.monitor call found",
            suggestion: "Replace with Foundation.MonitorManager.monitor/2"
          }
          | issues
        ]
      else
        issues
      end

    # Check for monitor references without cleanup
    issues =
      if String.contains?(line, "= Process.monitor") and
           not String.contains?(line, "demonitor") do
        [
          %{
            line: line_num,
            type: :missing_cleanup,
            message: "Monitor created but cleanup not visible",
            suggestion: "Ensure monitor is cleaned up in terminate/2 or use monitor_with_cleanup/3"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp add_structural_issues(line_issues, content) do
    structural_issues = []

    # Check if GenServer but no terminate callback
    structural_issues =
      if String.contains?(content, "use GenServer") and
           not String.contains?(content, "def terminate") do
        [
          %{
            line: 0,
            type: :missing_terminate,
            message: "GenServer without terminate/2 callback",
            suggestion: "Add terminate/2 callback to clean up monitors"
          }
          | structural_issues
        ]
      else
        structural_issues
      end

    # Check if has monitors but no MonitorManager alias
    structural_issues =
      if String.contains?(content, "Process.monitor") and
           not String.contains?(content, "MonitorManager") do
        [
          %{
            line: 0,
            type: :missing_alias,
            message: "Uses monitors but no MonitorManager alias",
            suggestion: "Add 'alias Foundation.MonitorManager' to module"
          }
          | structural_issues
        ]
      else
        structural_issues
      end

    line_issues ++ structural_issues
  end

  defp generate_report_text(
         directory,
         total_files,
         files_with_monitors,
         issues_by_file,
         total_issues
       ) do
    """

    === Monitor Migration Report for #{directory} ===

    ## Summary
    - Total files scanned: #{total_files}
    - Files with monitors: #{length(files_with_monitors)}
    - Total issues found: #{total_issues}
    - Migration needed: #{if length(files_with_monitors) > 0, do: "YES", else: "NO"}

    ## Files Requiring Migration
    #{format_files_with_issues(issues_by_file)}

    ## Recommended Migration Steps

    1. Add Foundation.MonitorManager to supervision tree
    2. For each file with issues:
       - Add 'alias Foundation.MonitorManager' 
       - Replace Process.monitor calls with MonitorManager.monitor
       - Add monitor cleanup in terminate/2 callbacks
       - Add handle_info for DOWN message handling
    3. Run tests to verify functionality
    4. Use MonitorManager.find_leaks/1 to detect any remaining issues

    ## Automated Migration

    To automatically migrate files:

        # For each file
        {:ok, content} = File.read(file_path)
        migrated = Foundation.MonitorMigration.migrate_genserver_module(content)
        File.write!(file_path, migrated)

    ## Next Steps

    1. Review each file manually for complex monitor usage
    2. Test thoroughly after migration
    3. Monitor production logs for MonitorManager warnings
    4. Use MonitorManager.get_stats/0 to track monitor health
    """
  end

  defp format_files_with_issues(issues_by_file) do
    if length(issues_by_file) == 0 do
      "  (No files with monitor issues found)"
    else
      issues_by_file
      |> Enum.map(fn {file, issues} ->
        issue_summary =
          issues
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {type, type_issues} ->
            "#{type}: #{length(type_issues)}"
          end)
          |> Enum.join(", ")

        "  - #{file} (#{issue_summary})"
      end)
      |> Enum.join("\n")
    end
  end
end
