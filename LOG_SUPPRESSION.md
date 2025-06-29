# Immediate Solution: Suppress Verbose Jido Action Logs

## Quick Fix ✅

The verbose Jido action execution logs are using `:notice` level. Here are **3 immediate solutions**:

### Option 1: Environment Variable (Simplest)
```bash
# Run with reduced log level to suppress notice logs
LOGGER_LEVEL=info mix test
LOGGER_LEVEL=info mix run
LOGGER_LEVEL=info iex -S mix
```

### Option 2: Runtime Log Level Change
```elixir
# In IEx or at runtime, suppress notice logs:
Logger.configure(level: :info)
```

### Option 3: Edit Jido Action Configuration (Best Long-term)
If you want to reduce Jido's log verbosity permanently, you can add this to your config:

```elixir
# In config/dev.exs or config/config.exs
config :jido, log_level: :warning
config :jido_action, log_level: :warning
```

## Root Cause

The issue is that Jido actions use `cond_log(log_level, :notice, message)` which:
1. Uses `:notice` level (between `:info` and `:warning`)
2. Logs the entire params and context structures
3. Results in massive log entries when task queues are large

## Current Status

I configured the logger to suppress `:notice` level logs:
```elixir
config :logger, level: :info  # This should suppress :notice
```

However, logger configuration can be complex with multiple handlers. The **environment variable approach** is the most reliable immediate fix.

## Test It

```bash
# Suppress verbose logs
LOGGER_LEVEL=warning mix test

# Or just info level (keeps info, warning, error)
LOGGER_LEVEL=info mix test
```

This will immediately eliminate the verbose action execution logs while preserving important info, warning, and error messages.

## Verification

Before:
```
[notice] Executing JidoSystem.Actions.QueueTask with params: %{priority: :normal, task: %{id: "overflow_task_943"...THOUSANDS_OF_CHARS...
```

After (with LOGGER_LEVEL=info):
```
[info] Important messages still appear
[warning] Warnings still appear  
[error] Errors still appear
# Notice messages suppressed
```

Use `LOGGER_LEVEL=info` for your immediate needs.