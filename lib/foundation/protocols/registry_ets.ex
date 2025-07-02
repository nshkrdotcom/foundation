defmodule Foundation.Protocols.RegistryETS do
  @moduledoc """
  ETS-based implementation of agent registry with process monitoring.

  This module provides a proper OTP-compliant registry that:
  - Uses ETS tables for storage instead of process dictionary
  - Monitors registered processes for automatic cleanup
  - Handles process death gracefully with proper demonitor
  - Maintains the same public API as the process dictionary implementation
  """

  use GenServer
  require Logger

  @table_name :foundation_agent_registry_ets
  @monitors_table :foundation_agent_monitors

  # Client API (maintains same interface as RegistryAny)

  @doc """
  Starts the ETS-based registry GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers an agent with the given ID and PID.
  Monitors the process for automatic cleanup on death.
  """
  def register_agent(agent_id, pid, metadata \\ %{}) when is_pid(pid) do
    ensure_started()
    GenServer.call(__MODULE__, {:register_agent, agent_id, pid, metadata})
  end

  @doc """
  Retrieves an agent by ID.
  Returns {:ok, pid} if found and alive, {:error, :not_found} otherwise.
  """
  def get_agent(agent_id) do
    ensure_table_exists()

    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, pid, _metadata, _ref}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          # Clean up dead process
          unregister_agent(agent_id)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all registered agents as {agent_id, pid} tuples.
  Only returns agents with alive processes.
  """
  def list_agents do
    ensure_table_exists()

    :ets.select(@table_name, [
      {{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])
    |> Enum.filter(fn {_id, pid, _metadata} -> Process.alive?(pid) end)
    |> Enum.map(fn {id, pid, _metadata} -> {id, pid} end)
  end

  @doc """
  Unregisters an agent by ID.
  """
  def unregister_agent(agent_id) do
    ensure_started()
    GenServer.call(__MODULE__, {:unregister_agent, agent_id})
  end

  @doc """
  Gets agent with metadata.
  Returns {:ok, {pid, metadata}} if found and alive, {:error, :not_found} otherwise.
  """
  def get_agent_with_metadata(agent_id) do
    ensure_table_exists()

    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, pid, metadata, _ref}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, {pid, metadata}}
        else
          # Clean up dead process
          unregister_agent(agent_id)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Updates metadata for a registered agent.
  """
  def update_metadata(agent_id, new_metadata) do
    ensure_started()
    GenServer.call(__MODULE__, {:update_metadata, agent_id, new_metadata})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ets.new(@monitors_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    Logger.info("Started ETS-based agent registry")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_agent, agent_id, pid, metadata}, _from, state) do
    # Check if already registered
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, _old_pid, _old_metadata, old_ref}] ->
        # Clean up old monitoring
        Process.demonitor(old_ref, [:flush])
        :ets.delete(@monitors_table, old_ref)

      [] ->
        :ok
    end

    # Monitor the new process
    ref = Process.monitor(pid)

    # Store in main table
    :ets.insert(@table_name, {agent_id, pid, metadata, ref})

    # Store reverse lookup for cleanup
    :ets.insert(@monitors_table, {ref, agent_id})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unregister_agent, agent_id}, _from, state) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, _pid, _metadata, ref}] ->
        # Demonitor the process
        Process.demonitor(ref, [:flush])

        # Clean up both tables
        :ets.delete(@table_name, agent_id)
        :ets.delete(@monitors_table, ref)

        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, pid, _old_metadata, ref}] ->
        :ets.insert(@table_name, {agent_id, pid, new_metadata, ref})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Handle process death
    case :ets.lookup(@monitors_table, ref) do
      [{^ref, agent_id}] ->
        # Clean up both tables
        :ets.delete(@table_name, agent_id)
        :ets.delete(@monitors_table, ref)

        Logger.debug("Cleaned up dead agent: #{agent_id}")

      [] ->
        # Monitor not found, ignore
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Ignore other messages
    {:noreply, state}
  end

  # Private helpers

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _pid} = start_link()
        :ok

      _pid ->
        :ok
    end
  end

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        ensure_started()
        # Give the GenServer a moment to create tables
        Process.sleep(10)

      _ ->
        :ok
    end
  end
end
