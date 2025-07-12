defmodule Foundation.Repository do
  @moduledoc """
  Repository pattern for ETS-based storage in Foundation.

  This module provides an abstraction over ETS tables, separating
  data access logic from business logic and providing a consistent
  interface for CRUD operations.

  ## Features

  - Type-safe ETS operations
  - Automatic table lifecycle management
  - Query builder pattern
  - Transaction support
  - Change tracking
  - Indexing support

  ## Usage

      defmodule MyApp.UserRepository do
        use Foundation.Repository,
          table_name: :users,
          key_type: :string,
          indexes: [:email, :status]

        # Define custom queries
        def find_by_email(email) do
          query()
          |> where(:email, :eq, email)
          |> one()
        end

        def active_users do
          query()
          |> where(:status, :eq, :active)
          |> order_by(:created_at, :desc)
          |> all()
        end
      end

      # Usage
      {:ok, user} = UserRepository.insert("user_1", %{
        email: "user@example.com",
        status: :active
      })

      {:ok, users} = UserRepository.active_users()
  """

  defmacro __using__(opts) do
    table_name = Keyword.fetch!(opts, :table_name)
    key_type = Keyword.get(opts, :key_type, :term)
    indexes = Keyword.get(opts, :indexes, [])

    quote do
      @behaviour Foundation.Repository.Behaviour

      @table_name unquote(table_name)
      @key_type unquote(key_type)
      @indexes unquote(indexes)
      @index_tables Enum.map(unquote(indexes), fn idx ->
                      :"#{unquote(table_name)}_#{idx}_idx"
                    end)

      use GenServer

      # Client API

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl Foundation.Repository.Behaviour
      def insert(key, value, opts \\ []) do
        GenServer.call(__MODULE__, {:insert, key, value, opts})
      end

      @impl Foundation.Repository.Behaviour
      def get(key, opts \\ []) do
        case :ets.lookup(@table_name, key) do
          [{^key, value, _metadata}] -> {:ok, value}
          [] -> {:error, :not_found}
        end
      end

      @impl Foundation.Repository.Behaviour
      def update(key, updates, opts \\ []) do
        GenServer.call(__MODULE__, {:update, key, updates, opts})
      end

      @impl Foundation.Repository.Behaviour
      def delete(key, opts \\ []) do
        GenServer.call(__MODULE__, {:delete, key, opts})
      end

      @impl Foundation.Repository.Behaviour
      def all(opts \\ []) do
        results =
          :ets.tab2list(@table_name)
          |> Enum.map(fn {_key, value, _metadata} -> value end)

        {:ok, results}
      end

      @impl Foundation.Repository.Behaviour
      def query do
        %Foundation.Repository.Query{
          repository: __MODULE__,
          table: @table_name,
          filters: [],
          order: nil,
          limit: nil
        }
      end

      @impl Foundation.Repository.Behaviour
      def transaction(fun) do
        GenServer.call(__MODULE__, {:transaction, fun})
      end

      # GenServer callbacks

      @impl true
      def init(_opts) do
        # Create main table
        :ets.new(@table_name, [:named_table, :public, :set])

        # Create index tables
        Enum.each(@indexes, fn index ->
          table_name = :"#{@table_name}_#{index}_idx"
          :ets.new(table_name, [:named_table, :public, :bag])
        end)

        # Register with ResourceManager
        Foundation.ResourceManager.register_ets_table(@table_name)
        Enum.each(@index_tables, &Foundation.ResourceManager.register_ets_table/1)

        state = %{
          table_name: @table_name,
          indexes: @indexes,
          transaction_log: []
        }

        {:ok, state}
      end

      @impl true
      def handle_call({:insert, key, value, opts}, _from, state) do
        metadata = %{
          created_at: System.system_time(:microsecond),
          updated_at: System.system_time(:microsecond)
        }

        # Insert into main table
        :ets.insert(@table_name, {key, value, metadata})

        # Update indexes
        update_indexes(key, value, :insert)

        # Emit event if configured
        if Keyword.get(opts, :emit_event, true) do
          Foundation.EventSystem.emit(:metric, [:repository, :insert], %{
            table: @table_name,
            key: key
          })
        end

        {:reply, {:ok, value}, state}
      end

      @impl true
      def handle_call({:update, key, updates, opts}, _from, state) do
        case :ets.lookup(@table_name, key) do
          [{^key, current_value, metadata}] ->
            # Apply updates
            new_value = Map.merge(current_value, updates)
            new_metadata = Map.put(metadata, :updated_at, System.system_time(:microsecond))

            # Remove old indexes
            update_indexes(key, current_value, :delete)

            # Update main table
            :ets.insert(@table_name, {key, new_value, new_metadata})

            # Add new indexes
            update_indexes(key, new_value, :insert)

            # Emit event
            if Keyword.get(opts, :emit_event, true) do
              Foundation.EventSystem.emit(:metric, [:repository, :update], %{
                table: @table_name,
                key: key,
                changes: Map.keys(updates)
              })
            end

            {:reply, {:ok, new_value}, state}

          [] ->
            {:reply, {:error, :not_found}, state}
        end
      end

      @impl true
      def handle_call({:delete, key, opts}, _from, state) do
        case :ets.lookup(@table_name, key) do
          [{^key, value, _metadata}] ->
            # Remove from indexes first
            update_indexes(key, value, :delete)

            # Delete from main table
            :ets.delete(@table_name, key)

            # Emit event
            if Keyword.get(opts, :emit_event, true) do
              Foundation.EventSystem.emit(:metric, [:repository, :delete], %{
                table: @table_name,
                key: key
              })
            end

            {:reply, :ok, state}

          [] ->
            {:reply, {:error, :not_found}, state}
        end
      end

      @impl true
      def handle_call({:transaction, fun}, _from, state) do
        # Simple transaction support - can be enhanced with proper rollback
        try do
          result = fun.()
          {:reply, {:ok, result}, state}
        rescue
          e ->
            {:reply, {:error, e}, state}
        end
      end

      # Private functions

      defp update_indexes(key, value, operation) do
        Enum.each(@indexes, fn index ->
          index_table = :"#{@table_name}_#{index}_idx"

          case Map.get(value, index) do
            nil ->
              :ok

            index_value ->
              case operation do
                :insert -> :ets.insert(index_table, {index_value, key})
                :delete -> :ets.delete_object(index_table, {index_value, key})
              end
          end
        end)
      end

      # Allow customization
      defoverridable init: 1, handle_call: 3
    end
  end
end
