defmodule JidoFoundation.Bridge.ExecutionManager do
  @moduledoc """
  Manages protected execution of Jido actions with Foundation infrastructure.

  This module provides circuit breakers, retries, and distributed execution
  for Jido agents using Foundation's production-grade infrastructure.
  """

  require Logger

  @doc """
  Executes a Jido action with Foundation circuit breaker protection.

  ## Options

  - `:timeout` - Action timeout in milliseconds
  - `:fallback` - Fallback value or function if circuit is open
  - `:service_id` - Circuit breaker identifier (defaults to agent PID)

  ## Examples

      ExecutionManager.execute_protected(agent, fn ->
        Jido.Action.execute(agent, :external_api_call, params)
      end)
  """
  def execute_protected(agent_pid, action_fun, opts \\ []) when is_function(action_fun, 0) do
    service_id = Keyword.get(opts, :service_id, {:jido_agent, agent_pid})

    # Wrap the action function to handle crashes gracefully
    protected_fun = fn ->
      try do
        action_fun.()
      catch
        :exit, reason ->
          Logger.warning("Jido action process exited: #{inspect(reason)}")
          fallback = Keyword.get(opts, :fallback, {:error, :process_exit})
          if is_function(fallback, 0), do: fallback.(), else: fallback

        kind, reason ->
          Logger.warning("Jido action crashed: #{kind} #{inspect(reason)}")
          fallback = Keyword.get(opts, :fallback, {:error, :action_crash})
          if is_function(fallback, 0), do: fallback.(), else: fallback
      end
    end

    Foundation.ErrorHandler.with_recovery(
      protected_fun,
      Keyword.merge(opts,
        strategy: :circuit_break,
        circuit_breaker: service_id,
        telemetry_metadata: %{
          agent_id: agent_pid,
          framework: :jido
        }
      )
    )
  end

  @doc """
  Executes a Jido action with retry logic and Foundation integration.

  ## Parameters

  - `action_module` - The action module to execute
  - `params` - Parameters to pass to the action (default: %{})
  - `context` - Execution context (default: %{})
  - `opts` - Execution options (default: [])

  ## Returns

  - `{:ok, result}` - On successful execution
  - `{:error, reason}` - On failure after all retries

  ## Examples

      {:ok, result} = execute_with_retry(MyAction, %{data: "test"})
      {:error, reason} = execute_with_retry(BadAction, %{})
  """
  @spec execute_with_retry(module(), map(), map(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def execute_with_retry(action_module, params \\ %{}, context \\ %{}, opts \\ []) do
    try do
      # Enhance context with Foundation metadata
      enhanced_context =
        Map.merge(context, %{
          foundation_bridge: true,
          agent_framework: :jido,
          timestamp: System.system_time(:microsecond)
        })

      # Extract Jido.Exec options
      exec_opts = [
        max_retries: Keyword.get(opts, :max_retries, 3),
        backoff: Keyword.get(opts, :backoff, 250),
        timeout: Keyword.get(opts, :timeout, 30_000),
        log_level: Keyword.get(opts, :log_level, :info)
      ]

      # Use Jido.Exec for proper action execution with built-in retry
      case Jido.Exec.run(action_module, params, enhanced_context, exec_opts) do
        {:ok, result} = success ->
          Logger.debug("Jido action executed successfully via Bridge",
            action: action_module,
            result: inspect(result)
          )

          success

        {:error, reason} = error ->
          Logger.warning("Jido action failed after retries via Bridge",
            action: action_module,
            reason: inspect(reason)
          )

          error
      end
    rescue
      error ->
        Logger.error("Exception during Jido action execution via Bridge",
          action: action_module,
          error: inspect(error)
        )

        {:error, {:execution_exception, error}}
    catch
      kind, value ->
        Logger.error("Caught #{kind} during Jido action execution via Bridge",
          action: action_module,
          value: inspect(value)
        )

        {:error, {:execution_caught, {kind, value}}}
    end
  end

  @doc """
  Executes a distributed operation across multiple Jido agents.

  Finds agents with the specified capability and executes the operation
  on each in parallel.

  ## Examples

      results = distributed_execute(:data_processing, fn agent ->
        GenServer.call(agent, {:process, data_chunk})
      end)
  """
  def distributed_execute(capability, operation_fun, opts \\ [])
      when is_function(operation_fun, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, 30_000)

    with {:ok, agents} <- JidoFoundation.Bridge.AgentManager.find_by_capability(capability, opts) do
      agent_pids = Enum.map(agents, fn {_key, pid, _metadata} -> pid end)

      # Early return if no agents found - no need to use TaskPoolManager
      if Enum.empty?(agent_pids) do
        {:ok, []}
      else
        # Use supervised task pool instead of Task.async_stream
        # Support isolated testing, registry testing, and production modes
        batch_result =
          cond do
            # Supervision testing mode - use isolated TaskPoolManager via ServiceDiscovery
            supervision_tree = Keyword.get(opts, :supervision_tree) ->
              Foundation.IsolatedServiceDiscovery.call_service(
                supervision_tree,
                JidoFoundation.TaskPoolManager,
                :execute_batch,
                [
                  :agent_operations,
                  agent_pids,
                  operation_fun,
                  max_concurrency: max_concurrency,
                  timeout: timeout,
                  on_timeout: :kill_task
                ]
              )

            # Registry testing mode - handle case where TaskPoolManager might not be available
            _registry = Keyword.get(opts, :registry) ->
              # In registry testing mode, we simulate task execution directly
              # since global TaskPoolManager might not be available
              try do
                # Try to execute the operation on each agent directly
                results =
                  agent_pids
                  |> Task.async_stream(
                    operation_fun,
                    max_concurrency: max_concurrency,
                    timeout: timeout,
                    on_timeout: :kill_task
                  )
                  |> Enum.map(fn
                    {:ok, result} -> {:ok, result}
                    {:exit, reason} -> {:error, reason}
                  end)

                {:ok, results}
              rescue
                e -> {:error, {:execution_failed, e}}
              end

            # Production mode - direct call to global TaskPoolManager
            true ->
              JidoFoundation.TaskPoolManager.execute_batch(
                :agent_operations,
                agent_pids,
                operation_fun,
                max_concurrency: max_concurrency,
                timeout: timeout,
                on_timeout: :kill_task
              )
          end

        case batch_result do
          {:ok, stream} ->
            results =
              stream
              |> Enum.map(fn
                {:ok, result} -> {:ok, result}
                {:exit, reason} -> {:error, reason}
              end)

            {:ok, results}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end
end
