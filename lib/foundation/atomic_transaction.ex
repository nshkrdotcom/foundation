defmodule Foundation.AtomicTransaction do
  @moduledoc """
  Provides transaction support for Foundation operations with manual rollback capabilities.

  IMPORTANT: Despite the module name, this does NOT provide true atomic transactions
  at the ETS level. Operations are serialized through the GenServer but ETS changes
  are NOT automatically rolled back on failure. This module helps track rollback
  data and provides manual rollback functionality.

  ## Features

  - Serial execution of operations (no interleaving)
  - Manual rollback support via tracked rollback data
  - Transaction logging for audit trail
  - Operation batching

  ## Limitations

  - NO automatic rollback of ETS operations on failure
  - Partial failures leave ETS in inconsistent state until manual rollback
  - Not suitable for true ACID requirements

  ## Usage

      Foundation.AtomicTransaction.transact(fn tx ->
        tx
        |> register_agent("agent_1", pid1, metadata1)
        |> register_agent("agent_2", pid2, metadata2)
        |> update_metadata("agent_3", new_metadata)
      end)
  """

  require Logger

  defstruct [:id, :operations, :state, :started_at, :registry_pid, :rollback_data]

  @type t :: %__MODULE__{
          id: String.t(),
          operations: list(operation()),
          state: :pending | :executing | :committed | :rolled_back,
          started_at: integer(),
          registry_pid: pid() | nil,
          rollback_data: list(rollback_info())
        }

  @type operation :: {atom(), list(any())}
  @type rollback_info :: {atom(), any()}

  @doc """
  Executes a function within an atomic transaction context.

  The function receives a transaction struct that accumulates operations.
  All operations are executed atomically - either all succeed or all are rolled back.

  ## Examples

      # Simple transaction
      {:ok, result} = Foundation.AtomicTransaction.transact(fn tx ->
        tx
        |> register_agent("agent_1", self(), %{capability: :ml})
        |> update_metadata("agent_2", %{status: :active})
      end)

      # Transaction with custom registry
      {:ok, result} = Foundation.AtomicTransaction.transact(registry_pid, fn tx ->
        tx
        |> register_agent("agent_1", self(), %{capability: :ml})
      end)
  """
  @spec transact((t() -> t())) :: {:ok, any()} | {:error, any()}
  def transact(fun) when is_function(fun, 1) do
    registry_pid = get_registry_pid()
    transact(registry_pid, fun)
  end

  @spec transact(pid() | nil, (t() -> t())) :: {:ok, any()} | {:error, any()}
  def transact(registry_pid, fun) when is_function(fun, 1) do
    tx = %__MODULE__{
      id: generate_transaction_id(),
      operations: [],
      state: :pending,
      started_at: System.monotonic_time(:microsecond),
      registry_pid: registry_pid,
      rollback_data: []
    }

    try do
      # Build the transaction
      tx = fun.(tx)

      # Execute the transaction
      execute_transaction(tx)
    rescue
      e ->
        Logger.error("Transaction #{tx.id} failed: #{Exception.message(e)}")
        {:error, {:transaction_failed, e}}
    end
  end

  @doc """
  Adds a register_agent operation to the transaction.
  """
  def register_agent(%__MODULE__{} = tx, agent_id, pid, metadata) do
    add_operation(tx, {:register, [agent_id, pid, metadata]})
  end

  @doc """
  Adds an update_metadata operation to the transaction.
  """
  def update_metadata(%__MODULE__{} = tx, agent_id, metadata) do
    add_operation(tx, {:update_metadata, [agent_id, metadata]})
  end

  @doc """
  Adds an unregister operation to the transaction.
  """
  def unregister(%__MODULE__{} = tx, agent_id) do
    add_operation(tx, {:unregister, [agent_id]})
  end

  @doc """
  Adds a custom operation to the transaction.

  The operation must be supported by the underlying registry implementation.
  """
  def add_operation(%__MODULE__{} = tx, {op_name, args} = operation)
      when is_atom(op_name) and is_list(args) do
    %{tx | operations: tx.operations ++ [operation]}
  end

  # Private Functions

  defp execute_transaction(%__MODULE__{operations: []} = tx) do
    # Empty transaction succeeds immediately
    {:ok, %{tx | state: :committed}}
  end

  defp execute_transaction(%__MODULE__{} = tx) do
    %{tx | state: :executing}
    |> execute_operations()
    |> case do
      {:ok, tx} ->
        log_transaction(tx, :committed)
        {:ok, %{tx | state: :committed}}

      {:error, reason, tx} ->
        rolled_back_tx = rollback_transaction(tx)
        log_transaction(rolled_back_tx, :rolled_back)
        {:error, reason}
    end
  end

  defp execute_operations(%__MODULE__{operations: ops, registry_pid: registry} = tx) do
    # Use GenServer.call with a special transaction wrapper
    case GenServer.call(registry, {:execute_serial_operations, ops, tx.id}) do
      {:ok, rollback_data} ->
        {:ok, %{tx | rollback_data: rollback_data}}

      {:error, reason, partial_rollback} ->
        {:error, reason, %{tx | rollback_data: partial_rollback}}

      {:error, :not_supported} ->
        # Fallback to sequential execution with manual rollback
        execute_operations_sequentially(tx)
    end
  catch
    :exit, reason ->
      {:error, {:registry_unavailable, reason}, tx}
  end

  defp execute_operations_sequentially(%__MODULE__{} = tx) do
    Enum.reduce_while(tx.operations, {:ok, tx}, fn operation, {:ok, acc_tx} ->
      case execute_single_operation(acc_tx.registry_pid, operation) do
        {:ok, rollback_info} ->
          updated_tx = %{acc_tx | rollback_data: acc_tx.rollback_data ++ [rollback_info]}
          {:cont, {:ok, updated_tx}}

        {:error, reason} ->
          {:halt, {:error, reason, acc_tx}}
      end
    end)
  end

  defp execute_single_operation(registry_pid, {:register, [agent_id, pid, metadata]}) do
    case Foundation.Registry.register(registry_pid, agent_id, pid, metadata) do
      :ok ->
        {:ok, {:unregister, agent_id}}

      error ->
        error
    end
  end

  defp execute_single_operation(registry_pid, {:update_metadata, [agent_id, new_metadata]}) do
    # First, get the old metadata for rollback
    case Foundation.Registry.lookup(registry_pid, agent_id) do
      {:ok, {_pid, old_metadata}} ->
        case Foundation.Registry.update_metadata(registry_pid, agent_id, new_metadata) do
          :ok ->
            {:ok, {:update_metadata, agent_id, old_metadata}}

          error ->
            error
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  defp execute_single_operation(registry_pid, {:unregister, [agent_id]}) do
    # First, get the agent info for rollback
    case Foundation.Registry.lookup(registry_pid, agent_id) do
      {:ok, {pid, metadata}} ->
        case Foundation.Registry.unregister(registry_pid, agent_id) do
          :ok ->
            {:ok, {:register, agent_id, pid, metadata}}

          error ->
            error
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  defp rollback_transaction(%__MODULE__{rollback_data: rollback_data, registry_pid: registry} = tx) do
    # Execute rollback operations in reverse order
    Enum.reverse(rollback_data)
    |> Enum.each(fn rollback_op ->
      execute_rollback_operation(registry, rollback_op)
    end)

    %{tx | state: :rolled_back}
  end

  defp execute_rollback_operation(registry_pid, {:register, agent_id, pid, metadata}) do
    # Best effort rollback - ignore errors
    Foundation.Registry.register(registry_pid, agent_id, pid, metadata)
    :ok
  end

  defp execute_rollback_operation(registry_pid, {:update_metadata, agent_id, old_metadata}) do
    Foundation.Registry.update_metadata(registry_pid, agent_id, old_metadata)
    :ok
  end

  defp execute_rollback_operation(registry_pid, {:unregister, agent_id}) do
    Foundation.Registry.unregister(registry_pid, agent_id)
    :ok
  end

  defp log_transaction(%__MODULE__{} = tx, final_state) do
    duration = System.monotonic_time(:microsecond) - tx.started_at

    Logger.info("""
    Transaction #{tx.id} #{final_state}:
      Operations: #{length(tx.operations)}
      Duration: #{duration}μs
      Registry: #{inspect(tx.registry_pid)}
    """)

    # Emit telemetry event
    :telemetry.execute(
      [:foundation, :transaction, final_state],
      %{duration: duration, operation_count: length(tx.operations)},
      %{transaction_id: tx.id, registry_pid: tx.registry_pid}
    )
  end

  defp generate_transaction_id do
    "tx_#{System.unique_integer([:positive, :monotonic])}_#{:rand.uniform(1_000_000)}"
  end

  defp get_registry_pid do
    # Try to get the configured registry implementation
    case Application.get_env(:foundation, :registry_impl) do
      nil -> nil
      impl -> impl
    end
  end
end
