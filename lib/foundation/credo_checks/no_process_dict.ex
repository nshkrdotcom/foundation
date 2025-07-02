defmodule Foundation.CredoChecks.NoProcessDict do
  @moduledoc """
  A custom Credo check that detects usage of Process.put/2 and Process.get/1,2.

  Process dictionary usage bypasses OTP supervision and makes testing difficult.
  Instead, use:
  - GenServer state for stateful processes
  - ETS tables for shared state
  - Explicit parameter passing for temporary state

  This check allows whitelisting specific modules during migration.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      allowed_modules: []
    ],
    explanations: [
      check: """
      Process dictionary bypasses OTP supervision and makes testing difficult.

      Instead of:
          Process.put(:key, value)
          Process.get(:key)

      Use one of these alternatives:

      1. GenServer state for stateful processes:
          def handle_call(:get_value, _from, state) do
            {:reply, state.value, state}
          end

      2. ETS tables for shared state:
          :ets.insert(:my_table, {:key, value})
          :ets.lookup(:my_table, :key)

      3. Explicit parameter passing for temporary state:
          def process_data(data, context) do
            # Pass context explicitly instead of using process dictionary
          end

      4. Logger metadata for error context:
          Logger.metadata(request_id: request_id)
      """,
      params: [
        allowed_modules:
          "A list of module names (as strings) that are allowed to use Process dictionary during migration"
      ]
    ]

  # Define empty module if Credo is not available
  if Code.ensure_loaded?(Credo.Check) do
    alias Credo.{Code, IssueMeta}

    @doc false
    def run(%Credo.SourceFile{} = source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)
      # Get allowed_modules directly from params list with default fallback
      allowed_modules = params[:allowed_modules] || []

      if should_check_file?(source_file, allowed_modules) do
        source_file
        |> Code.prewalk(&traverse(&1, &2, issue_meta))
      else
        []
      end
    end

    defp should_check_file?(source_file, allowed_modules) do
      filename = source_file.filename

      # Don't check test files
      return_false_if_test = String.contains?(filename, "/test/")

      # Check if file is in allowed modules list
      allowed =
        Enum.any?(allowed_modules, fn module ->
          module_path = String.replace(module, ".", "/")
          String.contains?(filename, module_path)
        end)

      not return_false_if_test and not allowed
    end

    # Detect Process.put/2
    defp traverse(
           {{:., _, [{:__aliases__, _, [:Process]}, :put]}, meta, args} = ast,
           issues,
           issue_meta
         )
         when is_list(args) and length(args) == 2 do
      issue =
        format_issue(
          issue_meta,
          message:
            "Avoid Process.put/2 - use GenServer state, ETS, or explicit parameter passing instead",
          line_no: meta[:line],
          column: meta[:column]
        )

      {ast, [issue | issues]}
    end

    # Detect Process.get/1 and Process.get/2
    defp traverse(
           {{:., _, [{:__aliases__, _, [:Process]}, :get]}, meta, args} = ast,
           issues,
           issue_meta
         )
         when is_list(args) and (length(args) == 1 or length(args) == 2) do
      issue =
        format_issue(
          issue_meta,
          message:
            "Avoid Process.get/#{length(args)} - use GenServer state, ETS, or explicit parameter passing instead",
          line_no: meta[:line],
          column: meta[:column]
        )

      {ast, [issue | issues]}
    end

    # Detect Process.get_keys/0 and Process.get_keys/1
    defp traverse(
           {{:., _, [{:__aliases__, _, [:Process]}, :get_keys]}, meta, args} = ast,
           issues,
           issue_meta
         )
         when is_list(args) do
      issue =
        format_issue(
          issue_meta,
          message: "Avoid Process.get_keys/#{length(args)} - indicates process dictionary usage",
          line_no: meta[:line],
          column: meta[:column]
        )

      {ast, [issue | issues]}
    end

    # Detect Process.delete/1
    defp traverse(
           {{:., _, [{:__aliases__, _, [:Process]}, :delete]}, meta, args} = ast,
           issues,
           issue_meta
         )
         when is_list(args) and length(args) == 1 do
      issue =
        format_issue(
          issue_meta,
          message: "Avoid Process.delete/1 - indicates process dictionary usage",
          line_no: meta[:line],
          column: meta[:column]
        )

      {ast, [issue | issues]}
    end

    # Detect Process.erase/0 and Process.erase/1
    defp traverse(
           {{:., _, [{:__aliases__, _, [:Process]}, :erase]}, meta, args} = ast,
           issues,
           issue_meta
         ) do
      issue =
        format_issue(
          issue_meta,
          message: "Avoid Process.erase/#{length(args)} - indicates process dictionary usage",
          line_no: meta[:line],
          column: meta[:column]
        )

      {ast, [issue | issues]}
    end

    defp traverse(ast, issues, _issue_meta) do
      {ast, issues}
    end

    defp format_issue(issue_meta, opts) do
      # Extract source file from issue_meta tuple
      {_meta_module, source_file, _params} = issue_meta

      %Credo.Issue{
        category: :warning,
        check: __MODULE__,
        filename: source_file.filename,
        line_no: opts[:line_no],
        column: opts[:column],
        message: opts[:message],
        priority: :high,
        trigger: opts[:trigger] || "Process dictionary usage"
      }
    end
  else
    @doc false
    def run(_source_file, _params), do: []
  end
end
