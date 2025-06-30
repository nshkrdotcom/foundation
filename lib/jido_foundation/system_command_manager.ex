defmodule JidoFoundation.SystemCommandManager do
  @moduledoc """
  Supervised system command execution with proper isolation and resource limits.

  This module provides safe execution of system commands with:
  - Dedicated supervisor for external processes
  - Timeout and resource limits
  - Proper cleanup on failure
  - Isolation from critical agent processes

  ## Features

  - Supervised execution of system commands
  - Configurable timeouts and resource limits
  - Command result caching to reduce system load
  - Proper error handling and recovery
  - Isolation from critical system processes

  ## Usage

      # Execute a system command safely
      {:ok, result} = JidoFoundation.SystemCommandManager.execute_command(
        "uptime",
        [],
        timeout: 5000
      )

      # Get cached system metrics
      {:ok, load_avg} = JidoFoundation.SystemCommandManager.get_load_average()
  """

  use GenServer
  require Logger

  defstruct [
    # Command result cache with TTL
    :cache,
    # %{command_key => %{result, timestamp, ttl}}
    :active_commands,
    # %{command_ref => %{command, started_at}}
    :config,
    :stats
  ]

  @type command_result :: {:ok, {binary(), non_neg_integer()}} | {:error, term()}

  # Default configuration
  @default_config %{
    # Default timeout for system commands
    default_timeout: 10_000,
    # Maximum concurrent system commands
    max_concurrent: 5,
    # Cache TTL for results (30 seconds)
    cache_ttl: 30_000,
    # Commands that are allowed to run
    allowed_commands: ["uptime", "ps", "free", "df", "iostat", "vmstat"]
  }

  # Client API

  @doc """
  Starts the system command manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a system command with supervision and resource limits.

  ## Parameters

  - `command` - Command to execute
  - `args` - Command arguments
  - `opts` - Execution options

  ## Options

  - `:timeout` - Command timeout in milliseconds (default: 10,000)
  - `:cache_ttl` - Cache result for this duration (default: 30,000)
  - `:use_cache` - Whether to use cached results (default: true)

  ## Returns

  - `{:ok, {output, exit_code}}` - Command executed successfully
  - `{:error, reason}` - Command failed or not allowed
  """
  @spec execute_command(binary(), [binary()], keyword()) :: command_result()
  def execute_command(command, args \\ [], opts \\ []) do
    GenServer.call(__MODULE__, {:execute_command, command, args, opts}, :infinity)
  end

  @doc """
  Gets system load average with caching.
  """
  @spec get_load_average() :: {:ok, float()} | {:error, term()}
  def get_load_average do
    case execute_command("uptime", [], cache_ttl: 30_000) do
      {:ok, {uptime, 0}} when is_binary(uptime) ->
        case Regex.run(~r/load average: ([\d.]+)/, uptime) do
          [_, load] ->
            case Float.parse(load) do
              {parsed_load, _} -> {:ok, parsed_load}
              :error -> {:ok, 0.0}
            end

          _ ->
            {:ok, 0.0}
        end

      {:ok, {_, _exit_code}} ->
        {:ok, 0.0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets system memory information with caching.
  """
  @spec get_memory_info() ::
          {:ok, %{total: integer(), available: integer(), used: integer()}} | {:error, term()}
  def get_memory_info do
    case execute_command("free", ["-b"], cache_ttl: 30_000) do
      {:ok, {output, 0}} ->
        memory_info = parse_memory_output(output)
        {:ok, memory_info}

      {:ok, {_, _exit_code}} ->
        {:ok, %{total: 0, available: 0, used: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets system command execution statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears the command result cache.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  @doc """
  Updates the allowed commands list.
  """
  @spec update_allowed_commands([binary()]) :: :ok
  def update_allowed_commands(commands) when is_list(commands) do
    GenServer.call(__MODULE__, {:update_allowed_commands, commands})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    config =
      @default_config
      |> Map.merge(Map.new(Keyword.get(opts, :config, [])))

    state = %__MODULE__{
      cache: %{},
      active_commands: %{},
      config: config,
      stats: %{
        commands_executed: 0,
        commands_cached: 0,
        commands_failed: 0,
        cache_hits: 0,
        active_count: 0
      }
    }

    Logger.info(
      "SystemCommandManager started with #{length(config.allowed_commands)} allowed commands"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:execute_command, command, args, opts}, from, state) do
    # Check if command is allowed
    if command in state.config.allowed_commands do
      timeout = Keyword.get(opts, :timeout, state.config.default_timeout)
      cache_ttl = Keyword.get(opts, :cache_ttl, state.config.cache_ttl)
      use_cache = Keyword.get(opts, :use_cache, true)

      # Generate cache key
      cache_key = {command, args}

      # Check cache first
      if use_cache do
        case get_cached_result(state.cache, cache_key) do
          {:ok, result} ->
            new_stats = Map.update!(state.stats, :cache_hits, &(&1 + 1))
            new_state = %{state | stats: new_stats}
            {:reply, {:ok, result}, new_state}

          :cache_miss ->
            execute_command_async(command, args, cache_key, cache_ttl, timeout, from, state)
        end
      else
        execute_command_async(command, args, cache_key, cache_ttl, timeout, from, state)
      end
    else
      {:reply, {:error, {:command_not_allowed, command}}, state}
    end
  end

  def handle_call({:update_allowed_commands, commands}, _from, state) do
    new_config = %{state.config | allowed_commands: commands}
    new_state = %{state | config: new_config}

    Logger.info("Updated allowed commands: #{inspect(commands)}")
    {:reply, :ok, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        cache_size: map_size(state.cache),
        active_commands: map_size(state.active_commands),
        allowed_commands: length(state.config.allowed_commands)
      })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    Logger.info("Cleared system command cache (#{map_size(state.cache)} entries)")
    new_state = %{state | cache: %{}}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:command_result, command_ref, result, cache_key, cache_ttl}, state) do
    case Map.get(state.active_commands, command_ref) do
      nil ->
        # Command reference not found, ignore
        {:noreply, state}

      %{from: from} ->
        # Reply to the waiting process
        GenServer.reply(from, result)

        # Update cache if successful
        new_cache =
          case result do
            {:ok, command_output} ->
              cache_entry = %{
                result: command_output,
                timestamp: System.monotonic_time(:millisecond),
                ttl: cache_ttl
              }

              Map.put(state.cache, cache_key, cache_entry)

            {:error, _} ->
              state.cache
          end

        # Update stats
        new_stats =
          case result do
            {:ok, _} -> Map.update!(state.stats, :commands_executed, &(&1 + 1))
            {:error, _} -> Map.update!(state.stats, :commands_failed, &(&1 + 1))
          end

        # Remove from active commands
        new_active_commands = Map.delete(state.active_commands, command_ref)

        new_state = %{
          state
          | cache: new_cache,
            active_commands: new_active_commands,
            stats: new_stats
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:command_timeout, command_ref}, state) do
    case Map.get(state.active_commands, command_ref) do
      nil ->
        {:noreply, state}

      %{from: from, pid: cmd_pid} ->
        # Kill the command process
        Process.exit(cmd_pid, :kill)

        # Reply with timeout error
        GenServer.reply(from, {:error, :timeout})

        # Update stats
        new_stats = Map.update!(state.stats, :commands_failed, &(&1 + 1))

        # Remove from active commands
        new_active_commands = Map.delete(state.active_commands, command_ref)

        new_state = %{
          state
          | active_commands: new_active_commands,
            stats: new_stats
        }

        Logger.warning("System command timed out: #{command_ref}")
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle command process exit
    command_ref =
      Enum.find_value(state.active_commands, fn {ref, %{pid: cmd_pid}} ->
        if cmd_pid == pid, do: ref, else: nil
      end)

    if command_ref do
      case Map.get(state.active_commands, command_ref) do
        %{from: from} ->
          # Only treat as error if process didn't exit normally
          # Normal exits usually mean the command completed successfully
          case reason do
            :normal ->
              # Process completed normally, likely already sent result
              # Don't reply with error, just clean up
              :ok

            _other_reason ->
              # Process crashed or was killed, this is an actual error
              GenServer.reply(from, {:error, {:process_exit, reason}})
          end

        _ ->
          :ok
      end

      new_active_commands = Map.delete(state.active_commands, command_ref)

      # Only increment failed count for abnormal exits
      new_stats =
        case reason do
          :normal -> state.stats
          _other -> Map.update!(state.stats, :commands_failed, &(&1 + 1))
        end

      new_state = %{
        state
        | active_commands: new_active_commands,
          stats: new_stats
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SystemCommandManager terminating: #{inspect(reason)}")

    # Kill all active command processes
    Enum.each(state.active_commands, fn {_ref, %{pid: pid}} ->
      try do
        Process.exit(pid, :shutdown)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  # Private helper functions

  defp execute_command_async(command, args, cache_key, cache_ttl, timeout, from, state) do
    # Check if we're at the concurrent limit
    if map_size(state.active_commands) >= state.config.max_concurrent do
      {:reply, {:error, :too_many_concurrent_commands}, state}
    else
      command_ref = make_ref()

      # Spawn supervised command execution
      manager_pid = self()

      cmd_pid =
        spawn_link(fn ->
          result =
            try do
              System.cmd(command, args, stderr_to_stdout: true)
            catch
              kind, reason ->
                {:error, {kind, reason}}
            end

          send(manager_pid, {:command_result, command_ref, {:ok, result}, cache_key, cache_ttl})
        end)

      # Monitor the command process
      Process.monitor(cmd_pid)

      # Set up timeout
      timeout_ref = Process.send_after(self(), {:command_timeout, command_ref}, timeout)

      # Track active command
      command_info = %{
        from: from,
        pid: cmd_pid,
        command: command,
        args: args,
        started_at: System.monotonic_time(:millisecond),
        timeout_ref: timeout_ref
      }

      new_active_commands = Map.put(state.active_commands, command_ref, command_info)
      new_state = %{state | active_commands: new_active_commands}

      {:noreply, new_state}
    end
  end

  defp get_cached_result(cache, cache_key) do
    case Map.get(cache, cache_key) do
      nil ->
        :cache_miss

      %{result: result, timestamp: timestamp, ttl: ttl} ->
        current_time = System.monotonic_time(:millisecond)

        if current_time - timestamp <= ttl do
          {:ok, result}
        else
          :cache_miss
        end
    end
  end

  defp parse_memory_output(output) do
    # Parse free command output
    # This is a simplified parser - could be made more robust
    lines = String.split(output, "\n")

    case Enum.find(lines, &String.starts_with?(&1, "Mem:")) do
      nil ->
        %{total: 0, available: 0, used: 0}

      mem_line ->
        # Remove "Mem:" prefix
        parts = String.split(mem_line) |> Enum.drop(1)

        case parts do
          [total, used, _free, _shared, _buff_cache, available | _] ->
            %{
              total: String.to_integer(total),
              used: String.to_integer(used),
              available: String.to_integer(available)
            }

          _ ->
            %{total: 0, available: 0, used: 0}
        end
    end
  rescue
    _ ->
      %{total: 0, available: 0, used: 0}
  end
end
