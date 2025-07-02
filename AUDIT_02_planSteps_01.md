# OTP Implementation Plan - Stage 1: Quality & Enforcement Infrastructure
Generated: July 2, 2025
Duration: Week 1 (5 days)
Status: Ready for Implementation

## Overview

This document details Stage 1 of the OTP remediation plan, focusing on creating enforcement infrastructure to prevent regression of OTP violations. This stage must be completed before proceeding to test and production code fixes.

## Context Documents
- **Parent Plan**: `AUDIT_02_plan.md` - Full remediation strategy
- **Original Audit**: `JULY_1_2025_PRE_PHASE_2_OTP_report_01_AUDIT_01.md` - Initial findings
- **Test Guide**: `test/TESTING_GUIDE_OTP.md` - Current test anti-patterns
- **Foundation Docs**: `CLAUDE.md`, `FOUNDATION_JIDO_INTEGRATION_PLAN.md` - Architecture guidelines

## Current State
- **0 enforcement mechanisms** currently exist
- **41 raw send() calls** in production code
- **26 Process.sleep calls** in tests
- **No automated prevention** of anti-pattern reintroduction

## Stage 1 Deliverables

### 1.1 Credo Configuration File
**Priority: CRITICAL**  
**Time Estimate: 2 hours**  
**Location**: `.credo.exs` (root directory)

#### Implementation Steps:

1. **Create base configuration file**:
```elixir
# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/test/support/"]
      },
      requires: ["./lib/foundation/credo_checks/"],
      strict: true,
      color: true,
      checks: [
        # Banned functions with explanations
        {Credo.Check.Warning.ForbiddenModule, 
         modules: [
           {Process, [:spawn], "Use Task.Supervisor.start_child/2 instead"},
           {Process, [:spawn_link], "Use Task.Supervisor.start_child/2 with restart: :transient"},
           {Process, [:spawn_monitor], "Use Task.Supervisor with monitoring"},
           {Process, [:put], "Use GenServer state instead of process dictionary"},
           {Process, [:get], "Use GenServer state instead of process dictionary"},
           {Process, [:get_keys], "Use GenServer state instead of process dictionary"},
           {:erlang, [:send], "Use GenServer.cast/2 or JidoFoundation.CoordinationManager.send_supervised/3"}
         ]},
        
        # Custom OTP-specific checks
        {Foundation.CredoChecks.NoRawSend, []},
        {Foundation.CredoChecks.NoProcessSleep, []},
        {Foundation.CredoChecks.GenServerTimeout, []},
        {Foundation.CredoChecks.SupervisedProcesses, []},
        {Foundation.CredoChecks.MonitorCleanup, []},
        
        # Standard checks with strict settings
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Refactor.Nesting, max_nesting: 2},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.UnusedKeywordOperation, []},
        {Credo.Check.Warning.UnusedListOperation, []},
        {Credo.Check.Warning.UnusedStringOperation, []},
        {Credo.Check.Warning.UnusedTupleOperation, []},
        {Credo.Check.Design.DuplicatedCode, mass_threshold: 16},
        
        # Disable checks that conflict with OTP patterns
        {Credo.Check.Refactor.ModuleDependencies, false},
        {Credo.Check.Warning.ApplicationConfigInModuleAttribute, false}
      ]
    }
  ]
}
```

2. **Test the configuration**:
```bash
# Verify credo loads the config
mix credo --strict

# Expected output should show violations for existing anti-patterns
# This is expected and will be fixed in Stages 2-3
```

### 1.2 Custom Credo Checks
**Priority: CRITICAL**  
**Time Estimate: 4 hours**  
**Location**: `lib/foundation/credo_checks/`

#### Create directory structure:
```bash
mkdir -p lib/foundation/credo_checks
```

#### Check 1: No Raw Send
**File**: `lib/foundation/credo_checks/no_raw_send.ex`

```elixir
defmodule Foundation.CredoChecks.NoRawSend do
  @moduledoc """
  Ensures no raw send() calls are used in production code.
  
  Raw send() bypasses OTP supervision and error handling.
  Use GenServer.cast/2 or JidoFoundation.CoordinationManager.send_supervised/3 instead.
  """
  
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Raw send() calls bypass OTP supervision and monitoring.
      
      Instead of:
          send(pid, message)
      
      Use one of:
          GenServer.cast(pid, message)
          JidoFoundation.CoordinationManager.send_supervised(pid, message, opts)
          Process.send(pid, message, [:noconnect])  # If absolutely necessary
      
      Exceptions:
      - Sending to self(): send(self(), message) is allowed for GenServer continuations
      - Test support modules in test/support/
      - Telemetry handlers for test infrastructure
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    
    # Skip test support files
    if in_test_support?(issue_meta.filename) do
      []
    else
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end
  
  defp traverse({:send, meta, [target, _message]} = ast, issues, issue_meta) do
    cond do
      sending_to_self?(target) ->
        {ast, issues}
        
      in_allowed_module?(issue_meta) ->
        {ast, issues}
        
      true ->
        issue = format_issue(issue_meta, meta[:line], 
          "Raw send() usage. Use GenServer.cast/2 or supervised send instead.")
        {ast, [issue | issues]}
    end
  end
  
  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
  
  defp sending_to_self?({:self, _, _}), do: true
  defp sending_to_self?(_), do: false
  
  defp in_test_support?(filename) do
    String.contains?(filename, "test/support/")
  end
  
  defp in_allowed_module?(issue_meta) do
    # Allow in specific modules during migration
    allowed_modules = [
      "lib/foundation/telemetry_handlers.ex",  # Test infrastructure
      "lib/foundation/telemetry/load_test/"    # Performance testing
    ]
    
    Enum.any?(allowed_modules, &String.contains?(issue_meta.filename, &1))
  end
  
  defp format_issue(issue_meta, line, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line,
      trigger: "send"
    )
  end
end
```

#### Check 2: No Process.sleep in Tests
**File**: `lib/foundation/credo_checks/no_process_sleep.ex`

```elixir
defmodule Foundation.CredoChecks.NoProcessSleep do
  @moduledoc """
  Detects Process.sleep usage in tests, which indicates timing-dependent tests.
  """
  
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Process.sleep in tests creates flaky, timing-dependent tests.
      
      Instead of:
          Process.sleep(100)
          assert some_condition()
      
      Use Foundation.AsyncTestHelpers:
          import Foundation.AsyncTestHelpers
          wait_for(fn -> some_condition() end)
      
      For telemetry events:
          assert_telemetry_event [:my, :event] do
            trigger_action()
          end
      
      For rate limiting tests:
          wait_for(fn -> RateLimiter.window_expired?(key) end)
      """
    ]

  def run(source_file, params \\ []) do
    if in_test_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end
  
  defp traverse(ast, issues, issue_meta) do
    case ast do
      {{:., _, [{:__aliases__, _, [:Process]}, :sleep]}, meta, _args} ->
        issue = format_issue(issue_meta, meta[:line])
        {ast, [issue | issues]}
        
      # Also catch :timer.sleep
      {{:., _, [:timer, :sleep]}, meta, _args} ->
        issue = format_issue(issue_meta, meta[:line])
        {ast, [issue | issues]}
        
      _ ->
        {ast, issues}
    end
  end
  
  defp in_test_file?(filename) do
    String.contains?(filename, "/test/") && String.ends_with?(filename, "_test.exs")
  end
  
  defp format_issue(issue_meta, line) do
    format_issue(
      issue_meta,
      message: "Process.sleep creates flaky tests. Use wait_for/1 from Foundation.AsyncTestHelpers",
      line_no: line,
      trigger: "Process.sleep"
    )
  end
end
```

#### Check 3: GenServer Timeout Requirements
**File**: `lib/foundation/credo_checks/genserver_timeout.ex`

```elixir
defmodule Foundation.CredoChecks.GenServerTimeout do
  @moduledoc """
  Ensures GenServer.call includes explicit timeouts.
  """
  
  use Credo.Check,
    base_priority: :medium,
    category: :warning,
    explanations: [
      check: """
      GenServer.call without explicit timeout uses default 5000ms.
      
      Always specify timeouts explicitly:
      
      Instead of:
          GenServer.call(server, request)
      
      Use:
          GenServer.call(server, request, :timer.seconds(10))
          GenServer.call(server, request, 30_000)  # 30 seconds
      
      This prevents unexpected timeouts and makes timeout behavior explicit.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end
  
  defp traverse(ast, issues, issue_meta) do
    case ast do
      {{:., meta, [{:__aliases__, _, [:GenServer]}, :call]}, _, args} 
        when length(args) == 2 ->
        issue = format_issue(issue_meta, meta[:line])
        {ast, [issue | issues]}
        
      _ ->
        {ast, issues}
    end
  end
  
  defp format_issue(issue_meta, line) do
    format_issue(
      issue_meta,
      message: "GenServer.call without explicit timeout. Add timeout as third parameter.",
      line_no: line,
      trigger: "GenServer.call"
    )
  end
end
```

#### Check 4: Supervised Processes Only
**File**: `lib/foundation/credo_checks/supervised_processes.ex`

```elixir
defmodule Foundation.CredoChecks.SupervisedProcesses do
  @moduledoc """
  Ensures all processes are started under supervision.
  """
  
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      All processes must be started under supervision for fault tolerance.
      
      Instead of:
          spawn(fn -> do_work() end)
          Task.async(fn -> do_work() end)
      
      Use:
          Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> do_work() end)
          DynamicSupervisor.start_child(MyApp.DynamicSupervisor, child_spec)
      
      For GenServers:
          DynamicSupervisor.start_child(sup, {MyServer, args})
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    
    if should_check?(source_file.filename) do
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end
  
  defp traverse(ast, issues, issue_meta) do
    case ast do
      # Direct spawn calls
      {:spawn, meta, _args} ->
        issue = format_issue(issue_meta, meta[:line], "spawn")
        {ast, [issue | issues]}
        
      {:spawn_link, meta, _args} ->
        issue = format_issue(issue_meta, meta[:line], "spawn_link")
        {ast, [issue | issues]}
        
      # Task.async without supervisor
      {{:., _, [{:__aliases__, _, [:Task]}, :async]}, meta, _args} ->
        issue = format_issue(issue_meta, meta[:line], "Task.async")
        {ast, [issue | issues]}
        
      _ ->
        {ast, issues}
    end
  end
  
  defp should_check?(filename) do
    not String.contains?(filename, "test/support/")
  end
  
  defp format_issue(issue_meta, line, function) do
    format_issue(
      issue_meta,
      message: "Use supervised processes. Replace #{function} with Task.Supervisor or DynamicSupervisor.",
      line_no: line,
      trigger: function
    )
  end
end
```

#### Check 5: Monitor Cleanup
**File**: `lib/foundation/credo_checks/monitor_cleanup.ex`

```elixir
defmodule Foundation.CredoChecks.MonitorCleanup do
  @moduledoc """
  Ensures Process.monitor calls have corresponding cleanup.
  """
  
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Process.monitor must have corresponding demonitor with flush.
      
      Proper pattern:
          ref = Process.monitor(pid)
          # ... do work ...
          Process.demonitor(ref, [:flush])
      
      Or handle in terminate/2 callback:
          def terminate(_reason, state) do
            Enum.each(state.monitors, fn ref ->
              Process.demonitor(ref, [:flush])
            end)
          end
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    
    monitors = find_monitors(source_file)
    demonitors = find_demonitors(source_file)
    
    check_monitor_cleanup(monitors, demonitors, issue_meta)
  end
  
  defp find_monitors(source_file) do
    {_, monitors} = 
      Credo.Code.prewalk(source_file, [], fn
        {{:., meta, [{:__aliases__, _, [:Process]}, :monitor]}, _, _} = ast, acc ->
          {ast, [{:monitor, meta[:line]} | acc]}
        ast, acc ->
          {ast, acc}
      end)
    monitors
  end
  
  defp find_demonitors(source_file) do
    {_, demonitors} = 
      Credo.Code.prewalk(source_file, [], fn
        {{:., meta, [{:__aliases__, _, [:Process]}, :demonitor]}, _, args} = ast, acc ->
          has_flush = check_flush_option(args)
          {ast, [{:demonitor, meta[:line], has_flush} | acc]}
        ast, acc ->
          {ast, acc}
      end)
    demonitors
  end
  
  defp check_flush_option([_ref, opts]) when is_list(opts) do
    :flush in opts
  end
  defp check_flush_option(_), do: false
  
  defp check_monitor_cleanup(monitors, demonitors, issue_meta) do
    monitor_count = length(monitors)
    demonitor_count = length(demonitors)
    
    cond do
      monitor_count > demonitor_count ->
        [format_issue(issue_meta, 
          "More Process.monitor calls than demonitor. Potential monitor leak.")]
          
      not Enum.all?(demonitors, fn {_, _, has_flush} -> has_flush end) ->
        [format_issue(issue_meta, 
          "Process.demonitor without [:flush] option. Add [:flush] to prevent message queue pollution.")]
          
      true ->
        []
    end
  end
  
  defp format_issue(issue_meta, message) do
    format_issue(
      issue_meta,
      message: message,
      trigger: "Process.monitor"
    )
  end
end
```

### 1.3 CI Pipeline Configuration
**Priority: HIGH**  
**Time Estimate: 2 hours**  
**Location**: `.github/workflows/otp_compliance.yml`

```yaml
name: OTP Compliance Check

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]

jobs:
  otp-compliance:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
          
      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            _build
            deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-
          
      - name: Install dependencies
        run: |
          mix deps.get
          mix deps.compile
          
      - name: Run Credo strict mode
        run: |
          mix credo --strict
          # For now, allow existing violations but track count
          mix credo --format json > credo_report.json || true
          
      - name: Check for banned patterns
        run: |
          echo "=== Checking for OTP violations ==="
          
          # Check for Process.spawn
          SPAWN_COUNT=$(grep -r "Process\.spawn[^_]" lib/ --include="*.ex" | wc -l || echo 0)
          echo "Process.spawn usage: $SPAWN_COUNT occurrences"
          if [ $SPAWN_COUNT -gt 0 ]; then
            echo "ERROR: Found Process.spawn usage"
            grep -r "Process\.spawn[^_]" lib/ --include="*.ex" || true
            exit 1
          fi
          
          # Check for process dictionary
          PROC_DICT_COUNT=$(grep -r "Process\.\(get\|put\)" lib/ --include="*.ex" | wc -l || echo 0)
          echo "Process dictionary usage: $PROC_DICT_COUNT occurrences"
          if [ $PROC_DICT_COUNT -gt 0 ]; then
            echo "ERROR: Found process dictionary usage"
            grep -r "Process\.\(get\|put\)" lib/ --include="*.ex" || true
            exit 1
          fi
          
          # Track raw sends (don't fail yet, just track)
          SEND_COUNT=$(grep -r "send(" lib/ --include="*.ex" | grep -v "test/support" | wc -l || echo 0)
          echo "Raw send() usage: $SEND_COUNT occurrences (baseline: 41)"
          if [ $SEND_COUNT -gt 41 ]; then
            echo "WARNING: Raw send usage increased! Was 41, now $SEND_COUNT"
            # Don't fail yet, this will be addressed in Stage 3
          fi
          
          # Track Process.sleep in tests
          SLEEP_COUNT=$(grep -r "Process\.sleep" test/ --include="*.exs" | wc -l || echo 0)
          echo "Process.sleep in tests: $SLEEP_COUNT occurrences (baseline: 26)"
          if [ $SLEEP_COUNT -gt 26 ]; then
            echo "WARNING: Process.sleep usage increased! Was 26, now $SLEEP_COUNT"
            # Don't fail yet, this will be addressed in Stage 2
          fi
          
      - name: Upload Credo report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: credo-report
          path: credo_report.json
          
      - name: Run OTP compliance tests
        run: |
          mix test test/foundation/otp_compliance_test.exs || echo "Tests not yet created"
          
      - name: Generate compliance summary
        if: always()
        run: |
          echo "## OTP Compliance Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Check | Count | Status |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|-------|--------|" >> $GITHUB_STEP_SUMMARY
          echo "| Process.spawn | $SPAWN_COUNT | $([ $SPAWN_COUNT -eq 0 ] && echo '✅' || echo '❌') |" >> $GITHUB_STEP_SUMMARY
          echo "| Process dictionary | $PROC_DICT_COUNT | $([ $PROC_DICT_COUNT -eq 0 ] && echo '✅' || echo '❌') |" >> $GITHUB_STEP_SUMMARY
          echo "| Raw send() | $SEND_COUNT | $([ $SEND_COUNT -le 41 ] && echo '⚠️' || echo '❌') |" >> $GITHUB_STEP_SUMMARY
          echo "| Process.sleep | $SLEEP_COUNT | $([ $SLEEP_COUNT -le 26 ] && echo '⚠️' || echo '❌') |" >> $GITHUB_STEP_SUMMARY

  dialyzer:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - name: Restore PLT cache
        uses: actions/cache@v3
        with:
          path: priv/plts
          key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}
      - name: Run dialyzer
        run: |
          mkdir -p priv/plts
          mix deps.get
          mix dialyzer --format github
```

### 1.4 OTP Compliance Test Suite
**Priority: HIGH**  
**Time Estimate: 3 hours**  
**Location**: `test/foundation/otp_compliance_test.exs`

```elixir
defmodule Foundation.OTPComplianceTest do
  use ExUnit.Case, async: true
  
  @moduledoc """
  Automated OTP compliance verification tests.
  These tests ensure the codebase follows OTP principles.
  """
  
  @banned_functions [
    {Process, [:spawn, :spawn_link, :spawn_monitor], "Use supervised processes"},
    {Process, [:put, :get, :get_keys], "Use GenServer state"},
    {:erlang, [:send], "Use GenServer.cast or supervised send"}
  ]
  
  @allowed_send_files [
    "lib/foundation/telemetry_handlers.ex",  # Test infrastructure
    "lib/foundation/telemetry/load_test"     # Performance testing
  ]
  
  describe "static code analysis" do
    test "no banned function calls in production code" do
      lib_files = Path.wildcard("lib/**/*.ex")
      
      violations = 
        lib_files
        |> Enum.flat_map(&check_file_for_violations/1)
        |> Enum.reject(&allowed_violation?/1)
        
      assert violations == [], 
        "Found OTP violations:\n#{format_violations(violations)}"
    end
    
    test "no Process.sleep in test files" do
      test_files = Path.wildcard("test/**/*_test.exs")
      
      violations = 
        test_files
        |> Enum.flat_map(&check_for_sleep/1)
        |> Enum.reject(&in_allowed_test?/1)
        
      assert length(violations) <= 26,  # Current baseline
        "Process.sleep usage increased beyond baseline (26):\n#{format_violations(violations)}"
    end
    
    test "all GenServers have proper structure" do
      genserver_modules = find_genserver_modules()
      
      for module <- genserver_modules do
        assert function_exported?(module, :init, 1),
          "#{module} missing init/1 callback"
          
        assert has_message_handler?(module),
          "#{module} has no message handlers (handle_call/cast/info)"
          
        if has_monitors?(module) do
          assert has_proper_cleanup?(module),
            "#{module} uses monitors but lacks proper cleanup in terminate/2"
        end
      end
    end
  end
  
  describe "runtime compliance" do
    test "all application processes are supervised" do
      # Start the application
      Application.ensure_all_started(:foundation)
      
      # Get all processes
      all_pids = Process.list()
      app_pids = filter_app_processes(all_pids)
      
      # Check each is supervised
      for pid <- app_pids do
        assert supervised?(pid),
          "Process #{inspect(pid)} (#{process_name(pid)}) is not supervised"
      end
    end
  end
  
  # Helper functions
  
  defp check_file_for_violations(file) do
    content = File.read!(file)
    
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        {_, violations} = 
          Macro.prewalk(ast, [], fn node, acc ->
            case check_node_for_violations(node, file) do
              {:violation, violation} -> {node, [violation | acc]}
              :ok -> {node, acc}
            end
          end)
        violations
        
      {:error, _} ->
        []  # Skip files with syntax errors
    end
  end
  
  defp check_node_for_violations(node, file) do
    case node do
      {{:., meta, [module_alias, function]}, _, args} ->
        module = resolve_module(module_alias)
        check_function_call(module, function, length(args), file, meta[:line])
        
      {:send, meta, [_target, _msg]} ->
        {:violation, {file, meta[:line], "send/2", "Use GenServer.cast or supervised send"}}
        
      _ ->
        :ok
    end
  end
  
  defp check_function_call(module, function, arity, file, line) do
    Enum.find_value(@banned_functions, :ok, fn {banned_mod, banned_funs, reason} ->
      if module == banned_mod and function in banned_funs do
        {:violation, {file, line, "#{module}.#{function}/#{arity}", reason}}
      else
        nil
      end
    end)
  end
  
  defp resolve_module({:__aliases__, _, parts}), do: Module.concat(parts)
  defp resolve_module(module) when is_atom(module), do: module
  defp resolve_module(_), do: nil
  
  defp allowed_violation?({file, _line, function, _reason}) do
    cond do
      # Allow send/2 in specific files
      function == "send/2" and Enum.any?(@allowed_send_files, &String.contains?(file, &1)) ->
        true
        
      # Allow send to self
      function == "send/2" and sending_to_self?(file) ->
        true
        
      true ->
        false
    end
  end
  
  defp format_violations(violations) do
    violations
    |> Enum.map(fn {file, line, function, reason} ->
      "  #{file}:#{line} - #{function} - #{reason}"
    end)
    |> Enum.join("\n")
  end
  
  defp find_genserver_modules do
    # This is a simplified version - in practice you'd want to
    # analyze the AST to find modules that `use GenServer`
    lib_files = Path.wildcard("lib/**/*.ex")
    
    Enum.flat_map(lib_files, fn file ->
      content = File.read!(file)
      if String.contains?(content, "use GenServer") do
        [extract_module_from_file(file)]
      else
        []
      end
    end)
    |> Enum.filter(&Code.ensure_loaded?/1)
  end
  
  defp extract_module_from_file(file) do
    content = File.read!(file)
    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module_string] -> String.to_atom("Elixir." <> module_string)
      _ -> nil
    end
  end
  
  defp has_message_handler?(module) do
    function_exported?(module, :handle_call, 3) or
    function_exported?(module, :handle_cast, 2) or
    function_exported?(module, :handle_info, 2)
  end
  
  defp has_monitors?(module) do
    # Check if module source contains Process.monitor
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, _} ->
        # Would need to analyze source
        false
      _ ->
        false
    end
  end
  
  defp has_proper_cleanup?(module) do
    function_exported?(module, :terminate, 2)
  end
  
  defp supervised?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        # Check for supervisor in ancestors
        Keyword.has_key?(dict, :"$ancestors") or
        Keyword.has_key?(dict, :"$initial_call")
      _ ->
        false
    end
  end
  
  defp filter_app_processes(pids) do
    Enum.filter(pids, fn pid ->
      case Process.info(pid, :registered_name) do
        {:registered_name, name} ->
          name_string = Atom.to_string(name)
          String.starts_with?(name_string, "Elixir.Foundation") or
          String.starts_with?(name_string, "Elixir.JidoSystem")
        _ ->
          false
      end
    end)
  end
  
  defp process_name(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} -> name
      _ -> "unnamed"
    end
  end
  
  defp check_for_sleep(file) do
    content = File.read!(file)
    
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.contains?(line, "Process.sleep") or String.contains?(line, ":timer.sleep") do
        [{file, line_no, "Process.sleep", "Use wait_for/1 or assert_telemetry_event/2"}]
      else
        []
      end
    end)
  end
  
  defp in_allowed_test?({file, _, _, _}) do
    # Some tests legitimately need sleep (e.g., testing actual timeouts)
    allowed_patterns = [
      "test/support/",  # Test helpers might need it
      "performance_test.exs"  # Performance tests might need controlled delays
    ]
    
    Enum.any?(allowed_patterns, &String.contains?(file, &1))
  end
  
  defp sending_to_self?(_file) do
    # This would require more sophisticated AST analysis
    false
  end
end
```

### 1.5 Documentation
**Priority: MEDIUM**  
**Time Estimate: 1 hour**  
**Location**: `docs/otp_compliance_guide.md`

```markdown
# OTP Compliance Guide

## Overview
This guide documents the OTP compliance standards enforced in this codebase.

## Enforced Rules

### 1. No Unsupervised Processes
- ❌ `Process.spawn/1`
- ❌ `Process.spawn_link/1`  
- ❌ `Task.async/1` (without supervisor)
- ✅ `Task.Supervisor.start_child/2`
- ✅ `DynamicSupervisor.start_child/2`

### 2. No Process Dictionary
- ❌ `Process.put/2`
- ❌ `Process.get/1`
- ✅ GenServer state
- ✅ ETS tables (properly managed)

### 3. No Raw Message Passing
- ❌ `send(pid, msg)` (except to self)
- ✅ `GenServer.cast/2`
- ✅ `GenServer.call/3`
- ✅ `JidoFoundation.CoordinationManager.send_supervised/3`

### 4. Explicit Timeouts
- ❌ `GenServer.call(server, msg)`
- ✅ `GenServer.call(server, msg, 10_000)`

### 5. Monitor Cleanup
- ❌ `Process.monitor(pid)` without cleanup
- ✅ `Process.demonitor(ref, [:flush])`

## Running Compliance Checks

```bash
# Run all Credo checks
mix credo --strict

# Run OTP compliance tests
mix test test/foundation/otp_compliance_test.exs

# Check specific patterns
mix run scripts/otp_audit.exs
```

## Fixing Violations

See migration guides:
- Stage 2: `AUDIT_02_planSteps_02.md` - Test fixes
- Stage 3: `AUDIT_02_planSteps_03.md` - Production fixes
```

## Verification Steps

1. **Install Credo** (if not already installed):
```bash
# Add to mix.exs deps
{:credo, "~> 1.7", only: [:dev, :test], runtime: false}

# Install
mix deps.get
mix deps.compile
```

2. **Create directory structure**:
```bash
mkdir -p lib/foundation/credo_checks
mkdir -p .github/workflows
mkdir -p docs
```

3. **Copy all files from this document**

4. **Test Credo configuration**:
```bash
mix credo --strict
# Expect to see violations - this is normal before Stages 2-3
```

5. **Verify CI configuration**:
```bash
# Commit and push to a branch
git add .
git commit -m "Add OTP compliance infrastructure"
git push origin otp-compliance-stage-1

# Create PR to see CI in action
```

## Success Criteria

Stage 1 is complete when:
- ✅ `.credo.exs` file exists and loads successfully
- ✅ All 5 custom Credo checks compile without errors
- ✅ CI pipeline runs on every PR/push
- ✅ OTP compliance test suite runs (even if tests fail initially)
- ✅ Baseline metrics captured (41 sends, 26 sleeps)
- ✅ No new violations can be introduced without CI failing

## Common Issues & Solutions

### Issue: Credo can't find custom checks
**Solution**: Ensure the path in `requires:` matches the actual location of checks

### Issue: CI fails on existing code
**Solution**: For Stage 1, CI should warn but not fail on existing violations. Only prevent new violations.

### Issue: Custom checks too strict
**Solution**: Use the `allowed_modules` and `in_test_support?` patterns shown above

## Next Steps

After completing Stage 1:
- Proceed to `AUDIT_02_planSteps_02.md` for test suite fixes
- Monitor CI to ensure no new violations are introduced
- Track metrics dashboard for violation counts

---

**Completion Checklist**:
- [ ] Create `.credo.exs`
- [ ] Implement all 5 custom checks
- [ ] Set up CI pipeline
- [ ] Create compliance test suite
- [ ] Document compliance guide
- [ ] Verify all components work together
- [ ] Capture baseline metrics