defmodule Foundation.BatchOperations do
  @moduledoc """
  Provides optimized batch operations for Foundation registries.

  This module enables efficient bulk operations with:
  - Batch registration/unregistration
  - Bulk metadata updates
  - Optimized batch queries
  - Streaming result processing
  - Parallel execution options

  ## Performance Characteristics

  - Batch operations are executed atomically within registry
  - Parallel execution available for read operations
  - Streaming reduces memory usage for large result sets
  - Query optimization through index usage

  ## Usage

      # Batch register agents
      agents = [
        {"agent_1", pid1, %{capability: :ml}},
        {"agent_2", pid2, %{capability: :data}}
      ]

      {:ok, results} = Foundation.BatchOperations.batch_register(agents)

      # Stream query results
      Foundation.BatchOperations.stream_query([
        {[:capability], :ml, :eq}
      ])
      |> Stream.map(&process_agent/1)
      |> Enum.take(100)
  """

  require Logger
  alias Foundation.Registry

  @default_batch_size 1000
  @default_parallelism System.schedulers_online()

  @doc """
  Registers multiple agents in a single batch operation.

  ## Options

  - `:batch_size` - Number of operations per batch (default: 1000)
  - `:on_error` - Strategy for handling errors (:stop | :continue | :rollback)
  - `:timeout` - Operation timeout in milliseconds
  - `:registry` - Registry implementation to use

  ## Examples

      agents = [
        {"agent_1", pid1, metadata1},
        {"agent_2", pid2, metadata2}
      ]

      {:ok, results} = BatchOperations.batch_register(agents)

      # With error handling
      {:ok, results} = BatchOperations.batch_register(agents, on_error: :continue)
  """
  def batch_register(agents, opts \\ []) when is_list(agents) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_error = Keyword.get(opts, :on_error, :stop)
    registry = Keyword.get(opts, :registry)

    start_time = System.monotonic_time(:microsecond)

    results = process_registration_batches(agents, batch_size, on_error, registry)

    duration = System.monotonic_time(:microsecond) - start_time
    emit_batch_telemetry(:batch_register, length(agents), duration, results)

    results
  end

  defp process_registration_batches(agents, batch_size, on_error, registry) do
    agents
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, [], false}, fn batch, acc ->
      process_single_batch(batch, registry, on_error, acc)
    end)
    |> format_batch_result()
  end

  defp process_single_batch(batch, registry, on_error, {status, acc, had_errors}) do
    case execute_batch_register(batch, registry, on_error) do
      {:ok, batch_results} ->
        {:cont, {status, acc ++ batch_results, had_errors}}

      {:partial, batch_results} when on_error == :continue ->
        {:cont, {:partial, acc ++ batch_results, true}}

      error ->
        handle_batch_error(error, on_error, acc, registry)
    end
  end

  defp handle_batch_error(error, :stop, _acc, _registry) do
    {:halt, error}
  end

  defp handle_batch_error(_error, :rollback, acc, registry) do
    rollback_registrations(acc, registry)
    {:halt, {:error, :batch_failed}}
  end

  defp handle_batch_error(_error, :continue, acc, _registry) do
    {:cont, {:partial, acc, true}}
  end

  defp format_batch_result({:ok, ids, false}), do: {:ok, ids}
  defp format_batch_result({:ok, ids, true}), do: {:partial, ids}
  defp format_batch_result({:partial, ids, _}), do: {:partial, ids}
  defp format_batch_result(error), do: error

  @doc """
  Updates metadata for multiple agents in a single batch.

  ## Options

  - `:batch_size` - Number of operations per batch
  - `:parallel` - Execute updates in parallel (for non-atomic updates)
  - `:registry` - Registry implementation to use

  ## Examples

      updates = [
        {"agent_1", %{status: :active}},
        {"agent_2", %{status: :idle}}
      ]

      {:ok, results} = BatchOperations.batch_update_metadata(updates)
  """
  def batch_update_metadata(updates, opts \\ []) when is_list(updates) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    parallel = Keyword.get(opts, :parallel, false)
    registry = Keyword.get(opts, :registry)

    start_time = System.monotonic_time(:microsecond)

    results =
      if parallel do
        execute_parallel_updates(updates, registry)
      else
        execute_sequential_updates(updates, batch_size, registry)
      end

    duration = System.monotonic_time(:microsecond) - start_time
    emit_batch_telemetry(:batch_update, length(updates), duration, results)

    results
  end

  @doc """
  Performs optimized batch query with multiple criteria.

  Returns all results matching ALL criteria (AND operation).

  ## Options

  - `:limit` - Maximum number of results
  - `:offset` - Number of results to skip
  - `:order_by` - Field to order results by
  - `:parallel` - Use parallel query execution
  - `:registry` - Registry implementation to use

  ## Examples

      # Find all healthy ML agents
      {:ok, agents} = BatchOperations.batch_query([
        {[:capability], :ml, :eq},
        {[:health_status], :healthy, :eq}
      ])

      # With pagination
      {:ok, agents} = BatchOperations.batch_query(criteria,
        limit: 100,
        offset: 200
      )
  """
  def batch_query(criteria, opts \\ []) when is_list(criteria) do
    registry = Keyword.get(opts, :registry)
    parallel = Keyword.get(opts, :parallel, true)

    start_time = System.monotonic_time(:microsecond)

    results =
      if parallel and length(criteria) > 1 do
        execute_parallel_query(criteria, registry, opts)
      else
        execute_sequential_query(criteria, registry, opts)
      end

    duration = System.monotonic_time(:microsecond) - start_time

    case results do
      {:ok, agents} ->
        emit_query_telemetry(criteria, length(agents), duration)
        apply_pagination(agents, opts)

      error ->
        error
    end
  end

  @doc """
  Creates a stream for processing large query results.

  Useful for processing large result sets without loading all into memory.

  ## Options

  - `:chunk_size` - Number of results per chunk (default: 100)
  - `:registry` - Registry implementation to use

  ## Examples

      BatchOperations.stream_query([{[:capability], :ml, :eq}])
      |> Stream.map(&process_agent/1)
      |> Stream.filter(&active?/1)
      |> Enum.take(1000)
  """
  def stream_query(criteria, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    registry = Keyword.get(opts, :registry)

    Stream.resource(
      fn -> {0, nil} end,
      fn {offset, _last_chunk} ->
        case batch_query(
               criteria,
               Keyword.merge(opts,
                 limit: chunk_size,
                 offset: offset,
                 registry: registry
               )
             ) do
          {:ok, []} ->
            {:halt, nil}

          {:ok, agents} when length(agents) < chunk_size ->
            {agents, {offset + length(agents), :done}}

          {:ok, agents} ->
            {agents, {offset + chunk_size, agents}}

          {:error, _reason} ->
            {:halt, nil}
        end
      end,
      fn _state -> :ok end
    )
  end

  @doc """
  Unregisters multiple agents in batch.

  ## Options

  - `:batch_size` - Number of operations per batch
  - `:ignore_missing` - Don't error on missing agents
  - `:registry` - Registry implementation to use
  """
  def batch_unregister(agent_ids, opts \\ []) when is_list(agent_ids) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    ignore_missing = Keyword.get(opts, :ignore_missing, false)
    registry = Keyword.get(opts, :registry)

    start_time = System.monotonic_time(:microsecond)

    results =
      agent_ids
      |> Stream.chunk_every(batch_size)
      |> Enum.map(fn batch ->
        execute_batch_unregister(batch, registry, ignore_missing)
      end)
      |> merge_batch_results()

    duration = System.monotonic_time(:microsecond) - start_time
    emit_batch_telemetry(:batch_unregister, length(agent_ids), duration, results)

    results
  end

  @doc """
  Performs parallel operations on agents matching criteria.

  Executes the given function on each matching agent in parallel.

  ## Options

  - `:max_concurrency` - Maximum parallel operations
  - `:timeout` - Timeout per operation
  - `:registry` - Registry implementation to use

  ## Examples

      # Update all ML agents in parallel
      BatchOperations.parallel_map(
        [{[:capability], :ml, :eq}],
        fn {id, pid, metadata} ->
          GenServer.call(pid, :update_state)
        end,
        max_concurrency: 10
      )
  """
  def parallel_map(criteria, fun, opts \\ []) when is_function(fun, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_parallelism)
    timeout = Keyword.get(opts, :timeout, 5000)

    stream_query(criteria, opts)
    |> Task.async_stream(fun,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:error, reason}
    end)
  end

  # Private functions

  defp execute_batch_register(batch, registry, on_error) do
    registry = registry || get_registry_impl()

    try_batch_register(batch, registry, on_error)
  catch
    :exit, _reason ->
      # Registry not available, try sequential
      execute_sequential_register(batch, registry, on_error)
  end

  defp try_batch_register(batch, registry, on_error) do
    case GenServer.call(registry, {:batch_register, batch}) do
      {:ok, results} ->
        {:ok, results}

      {:error, {:batch_register_failed, _failed_id, _reason}, registered_ids}
      when on_error == :continue and is_list(registered_ids) ->
        # Partial success - return the IDs that were registered
        {:partial, registered_ids}

      {:error, :not_supported} ->
        # Fallback to sequential registration
        fallback_to_sequential(batch, registry, on_error)

      error ->
        error
    end
  end

  defp fallback_to_sequential(batch, registry, on_error) do
    results =
      Enum.map(batch, fn {id, pid, metadata} ->
        try_register_single(registry, id, pid, metadata)
      end)

    handle_batch_results(results, on_error)
  end

  defp try_register_single(registry, id, pid, metadata) do
    case Registry.register(registry, id, pid, metadata) do
      :ok -> {:ok, id}
      {:error, reason} -> {:error, {id, reason}}
    end
  end

  defp execute_sequential_register(batch, registry, on_error) do
    results =
      Enum.map(batch, fn {id, pid, metadata} ->
        case Registry.register(registry, id, pid, metadata) do
          :ok -> {:ok, id}
          {:error, reason} -> {:error, {id, reason}}
        end
      end)

    handle_batch_results(results, on_error)
  end

  defp execute_parallel_updates(updates, registry) do
    registry = registry || get_registry_impl()

    updates
    |> Task.async_stream(
      fn {id, metadata} ->
        case Registry.update_metadata(registry, id, metadata) do
          :ok -> {:ok, id}
          error -> {:error, {id, error}}
        end
      end,
      max_concurrency: @default_parallelism
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
    |> handle_batch_results(:continue)
  end

  defp execute_sequential_updates(updates, batch_size, registry) do
    registry = registry || get_registry_impl()

    updates
    |> Stream.chunk_every(batch_size)
    |> Enum.flat_map(&process_update_batch(&1, registry))
    |> handle_batch_results(:continue)
  end

  defp process_update_batch(batch, registry) do
    Enum.map(batch, &execute_single_update(&1, registry))
  end

  defp execute_single_update({id, metadata}, registry) do
    case Registry.update_metadata(registry, id, metadata) do
      :ok -> {:ok, id}
      error -> {:error, {id, error}}
    end
  end

  defp execute_parallel_query(criteria, registry, _opts) do
    registry = registry || get_registry_impl()

    # Get indexed attributes
    indexed = Registry.indexed_attributes(registry)

    # Separate indexed and non-indexed criteria
    {indexed_criteria, other_criteria} =
      Enum.split_with(criteria, fn {[attr], _, _} ->
        attr in indexed
      end)

    case indexed_criteria do
      [] ->
        # No optimization possible
        Registry.query(registry, criteria)

      _ ->
        execute_optimized_query(indexed_criteria, other_criteria, registry)
    end
  end

  defp execute_optimized_query(indexed_criteria, other_criteria, registry) do
    # Query indexed criteria in parallel
    indexed_results = parallel_indexed_query(indexed_criteria, registry)

    case indexed_results do
      nil ->
        {:error, :query_failed}

      results ->
        final_results = apply_remaining_criteria(results, other_criteria)
        {:ok, final_results}
    end
  end

  defp parallel_indexed_query(indexed_criteria, registry) do
    indexed_criteria
    |> Task.async_stream(
      fn criterion ->
        Registry.query(registry, [criterion])
      end,
      max_concurrency: @default_parallelism
    )
    |> Enum.reduce(nil, fn
      {:ok, {:ok, agents}}, nil -> MapSet.new(agents)
      {:ok, {:ok, agents}}, acc -> MapSet.intersection(acc, MapSet.new(agents))
      _, acc -> acc
    end)
  end

  defp apply_remaining_criteria(indexed_results, other_criteria) do
    case other_criteria do
      [] ->
        MapSet.to_list(indexed_results)

      _ ->
        indexed_results
        |> MapSet.to_list()
        |> Enum.filter(fn agent ->
          matches_all_criteria?(agent, other_criteria)
        end)
    end
  end

  defp execute_sequential_query(criteria, registry, _opts) do
    registry = registry || get_registry_impl()
    Registry.query(registry, criteria)
  end

  defp apply_pagination(agents, opts) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by)

    sorted =
      if order_by do
        Enum.sort_by(agents, fn {_id, _pid, metadata} ->
          get_in(metadata, List.wrap(order_by))
        end)
      else
        agents
      end

    paginated =
      sorted
      |> Enum.drop(offset)
      |> then(fn list ->
        if limit, do: Enum.take(list, limit), else: list
      end)

    {:ok, paginated}
  end

  defp execute_batch_unregister(batch, registry, ignore_missing) do
    registry = registry || get_registry_impl()

    results =
      Enum.map(batch, fn id ->
        case Foundation.unregister(id, registry) do
          :ok -> {:ok, id}
          {:error, :not_found} when ignore_missing -> {:ok, id}
          error -> {:error, {id, error}}
        end
      end)

    handle_batch_results(results, :continue)
  end

  defp handle_batch_results(results, on_error) do
    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    case {errors, on_error} do
      {[], _} ->
        {:ok, Enum.map(successes, fn {:ok, id} -> id end)}

      {errors, :stop} ->
        {:error, errors}

      {_errors, :continue} ->
        {:partial, Enum.map(successes, fn {:ok, id} -> id end)}

      {_errors, :rollback} ->
        {:error, :needs_rollback}
    end
  end

  defp rollback_registrations(registered_ids, registry) do
    Enum.each(registered_ids, fn id ->
      Registry.unregister(registry, id)
    end)
  end

  defp merge_batch_results(results) do
    Enum.reduce(results, {:ok, []}, fn
      {:ok, ids}, {:ok, acc} -> {:ok, acc ++ ids}
      {:partial, ids}, {:ok, acc} -> {:partial, acc ++ ids}
      {:partial, ids}, {:partial, acc} -> {:partial, acc ++ ids}
      error, _acc -> error
    end)
  end

  defp matches_all_criteria?(agent, criteria) do
    Enum.all?(criteria, fn criterion ->
      matches_criterion?(agent, criterion)
    end)
  end

  defp matches_criterion?({_id, _pid, metadata}, {path, value, op}) do
    actual = get_in(metadata, path)
    apply_operation(actual, value, op)
  end

  defp apply_operation(actual, expected, :eq), do: actual == expected
  defp apply_operation(actual, expected, :neq), do: actual != expected
  defp apply_operation(actual, expected, :gt), do: actual > expected
  defp apply_operation(actual, expected, :lt), do: actual < expected
  defp apply_operation(actual, expected, :gte), do: actual >= expected
  defp apply_operation(actual, expected, :lte), do: actual <= expected
  defp apply_operation(actual, expected, :in) when is_list(expected), do: actual in expected
  defp apply_operation(actual, expected, :not_in) when is_list(expected), do: actual not in expected

  defp get_registry_impl do
    Application.get_env(:foundation, :registry_impl)
  end

  # Telemetry helpers

  defp emit_batch_telemetry(operation, count, duration, results) do
    success_count =
      case results do
        {:ok, items} -> length(items)
        {:partial, items} -> length(items)
        _ -> 0
      end

    :telemetry.execute(
      [:foundation, :batch_operations, operation],
      %{
        duration: duration,
        count: count,
        success_count: success_count,
        error_count: count - success_count
      },
      %{operation: operation}
    )
  end

  defp emit_query_telemetry(criteria, result_count, duration) do
    :telemetry.execute(
      [:foundation, :batch_operations, :query],
      %{
        duration: duration,
        result_count: result_count,
        criteria_count: length(criteria)
      },
      %{criteria: criteria}
    )
  end
end
