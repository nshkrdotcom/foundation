defmodule MLFoundation.AgentPatterns do
  @moduledoc """
  Foundation-level agent patterns for ML workloads.

  This module provides reusable agent patterns that can be used to build
  ML systems without coupling to specific ML frameworks. These patterns
  are designed to work with the Foundation infrastructure and can be
  extended by higher-level ML frameworks.

  ## Patterns Included

  1. **Pipeline Agent** - Sequential processing with state transformation
  2. **Ensemble Agent** - Aggregates results from multiple agents
  3. **Validator Agent** - Validates inputs/outputs against schemas
  4. **Transformer Agent** - Applies transformations to data
  5. **Optimizer Agent** - Iteratively improves solutions
  6. **Evaluator Agent** - Scores and ranks solutions

  ## Design Philosophy

  These patterns provide the building blocks for ML systems while remaining
  framework-agnostic. They integrate with Foundation's infrastructure for
  production-grade reliability and observability.
  """

  require Logger
  # alias Foundation.{Registry}

  # Pipeline Agent Pattern

  @doc """
  Creates a pipeline agent that processes data through sequential stages.

  ## Options

  - `:stages` - List of processing stages (functions or agent references)
  - `:error_strategy` - :halt, :skip, or :compensate (default: :halt)
  - `:telemetry_prefix` - Telemetry event prefix

  ## Examples

      {:ok, pipeline} = AgentPatterns.create_pipeline_agent([
        &normalize_data/1,
        &extract_features/1,
        &apply_transformation/1
      ])
  """
  def create_pipeline_agent(stages, opts \\ []) do
    GenServer.start_link(__MODULE__.PipelineAgent, {stages, opts})
  end

  @doc """
  Processes data through a pipeline agent.
  """
  def process_pipeline(agent, input, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(agent, {:process, input}, timeout)
  end

  # Ensemble Agent Pattern

  @doc """
  Creates an ensemble agent that aggregates results from multiple sources.

  ## Options

  - `:members` - List of agent PIDs or functions to ensemble
  - `:aggregation` - Aggregation strategy (:majority, :average, :weighted, custom function)
  - `:min_responses` - Minimum responses required (default: majority)

  ## Examples

      {:ok, ensemble} = AgentPatterns.create_ensemble_agent(
        members: [agent1, agent2, agent3],
        aggregation: :majority
      )
  """
  def create_ensemble_agent(opts) do
    GenServer.start_link(__MODULE__.EnsembleAgent, opts)
  end

  @doc """
  Gets ensemble prediction/result.
  """
  def ensemble_predict(agent, input, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(agent, {:predict, input}, timeout)
  end

  # Validator Agent Pattern

  @doc """
  Creates a validator agent that ensures data meets specifications.

  ## Options

  - `:schema` - Validation schema or function
  - `:on_invalid` - Action on invalid data (:reject, :fix, :log)
  - `:custom_validators` - List of custom validation functions

  ## Examples

      {:ok, validator} = AgentPatterns.create_validator_agent(
        schema: %{
          input_shape: {nil, 784},
          output_classes: 10
        }
      )
  """
  def create_validator_agent(opts) do
    GenServer.start_link(__MODULE__.ValidatorAgent, opts)
  end

  @doc """
  Validates data through the validator agent.
  """
  def validate(agent, data, opts \\ []) do
    GenServer.call(agent, {:validate, data, opts})
  end

  # Transformer Agent Pattern

  @doc """
  Creates a transformer agent for data transformations.

  ## Options

  - `:transformations` - Map of named transformations
  - `:cache_results` - Whether to cache transformation results
  - `:batch_size` - Process in batches if specified

  ## Examples

      {:ok, transformer} = AgentPatterns.create_transformer_agent(
        transformations: %{
          normalize: &normalize_fn/1,
          augment: &augment_fn/1
        }
      )
  """
  def create_transformer_agent(opts) do
    GenServer.start_link(__MODULE__.TransformerAgent, opts)
  end

  @doc """
  Applies a transformation through the agent.
  """
  def transform(agent, data, transformation_name, opts \\ []) do
    GenServer.call(agent, {:transform, data, transformation_name, opts})
  end

  # Optimizer Agent Pattern

  @doc """
  Creates an optimizer agent that iteratively improves solutions.

  ## Options

  - `:objective_fn` - Function to optimize
  - `:strategy` - Optimization strategy (:hill_climb, :genetic, :gradient, custom)
  - `:max_iterations` - Maximum iterations (default: 100)
  - `:convergence_threshold` - Stop when improvement < threshold

  ## Examples

      {:ok, optimizer} = AgentPatterns.create_optimizer_agent(
        objective_fn: &calculate_loss/1,
        strategy: :hill_climb,
        max_iterations: 1000
      )
  """
  def create_optimizer_agent(opts) do
    GenServer.start_link(__MODULE__.OptimizerAgent, opts)
  end

  @doc """
  Runs optimization through the agent.
  """
  def optimize(agent, initial_solution, opts \\ []) do
    # 5 minutes default
    timeout = Keyword.get(opts, :timeout, 300_000)
    GenServer.call(agent, {:optimize, initial_solution}, timeout)
  end

  # Evaluator Agent Pattern

  @doc """
  Creates an evaluator agent that scores and ranks solutions.

  ## Options

  - `:metrics` - List of metric functions
  - `:weights` - Weights for each metric (for composite scores)
  - `:ranking_strategy` - How to rank (:score, :pareto, custom)

  ## Examples

      {:ok, evaluator} = AgentPatterns.create_evaluator_agent(
        metrics: [&accuracy/2, &precision/2, &recall/2],
        weights: [0.5, 0.25, 0.25]
      )
  """
  def create_evaluator_agent(opts) do
    GenServer.start_link(__MODULE__.EvaluatorAgent, opts)
  end

  @doc """
  Evaluates solutions through the agent.
  """
  def evaluate(agent, solutions, opts \\ []) do
    GenServer.call(agent, {:evaluate, solutions, opts})
  end

  # Composite Patterns

  @doc """
  Creates a multi-stage ML workflow using multiple agent patterns.

  ## Examples

      {:ok, workflow} = AgentPatterns.create_ml_workflow(%{
        stages: [
          {:validator, [schema: input_schema]},
          {:transformer, [transformations: %{normalize: &norm/1}]},
          {:ensemble, [members: predictors, aggregation: :average]},
          {:evaluator, [metrics: [&accuracy/2]]}
        ]
      })
  """
  def create_ml_workflow(config) do
    with {:ok, agents} <- create_workflow_agents(config.stages),
         {:ok, coordinator} <- create_workflow_coordinator(agents, config) do
      {:ok, %{agents: agents, coordinator: coordinator}}
    end
  end

  # Private helper functions

  defp create_workflow_agents(stages) do
    agents =
      Enum.reduce_while(stages, [], fn {type, opts}, acc ->
        case create_agent_for_type(type, opts) do
          {:ok, agent} -> {:cont, [{type, agent} | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case agents do
      {:error, _} = error -> error
      agents -> {:ok, Enum.reverse(agents)}
    end
  end

  defp create_agent_for_type(type, opts) do
    case type do
      :pipeline -> create_pipeline_agent(opts[:stages], opts)
      :ensemble -> create_ensemble_agent(opts)
      :validator -> create_validator_agent(opts)
      :transformer -> create_transformer_agent(opts)
      :optimizer -> create_optimizer_agent(opts)
      :evaluator -> create_evaluator_agent(opts)
      _ -> {:error, {:unknown_agent_type, type}}
    end
  end

  defp create_workflow_coordinator(agents, config) do
    GenServer.start_link(__MODULE__.WorkflowCoordinator, {agents, config})
  end
end

# Implementation modules for each agent type

defmodule MLFoundation.AgentPatterns.PipelineAgent do
  @moduledoc """
  Agent for pipeline-based ML processing.
  Chains multiple processing stages together.
  """
  use GenServer
  require Logger

  def init({stages, opts}) do
    state = %{
      stages: stages,
      error_strategy: Keyword.get(opts, :error_strategy, :halt),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:ml_foundation, :pipeline]),
      stage_results: []
    }

    {:ok, state}
  end

  def handle_call({:process, input}, _from, state) do
    start_time = System.monotonic_time(:microsecond)

    result = process_stages(input, state.stages, state.error_strategy, [])

    duration = System.monotonic_time(:microsecond) - start_time

    emit_telemetry(state.telemetry_prefix, :completed, %{duration: duration}, %{
      stages: length(state.stages),
      success: elem(result, 0) == :ok
    })

    {:reply, result, state}
  end

  defp process_stages(data, [], _strategy, results) do
    {:ok, data, Enum.reverse(results)}
  end

  defp process_stages(data, [stage | rest], strategy, results) do
    case execute_stage(stage, data) do
      {:ok, transformed} ->
        process_stages(transformed, rest, strategy, [{:ok, transformed} | results])

      {:error, reason} = error ->
        case strategy do
          :halt ->
            error

          :skip ->
            process_stages(data, rest, strategy, [{:skipped, reason} | results])

          :compensate ->
            compensated = compensate_error(data, reason)
            process_stages(compensated, rest, strategy, [{:compensated, reason} | results])
        end
    end
  end

  defp execute_stage(stage, data) when is_function(stage, 1) do
    try do
      {:ok, stage.(data)}
    rescue
      e -> {:error, e}
    end
  end

  defp execute_stage(stage_pid, data) when is_pid(stage_pid) do
    try do
      GenServer.call(stage_pid, {:process, data}, 5000)
    catch
      :exit, reason -> {:error, {:stage_failed, reason}}
    end
  end

  defp compensate_error(data, _reason) do
    # Simple compensation - return original data
    # In real implementation, could have sophisticated recovery
    data
  end

  defp emit_telemetry(prefix, event, measurements, metadata) do
    :telemetry.execute(prefix ++ [event], measurements, metadata)
  end
end

defmodule MLFoundation.AgentPatterns.EnsembleAgent do
  @moduledoc """
  Agent for ensemble learning.
  Combines predictions from multiple models.
  """
  use GenServer
  require Logger

  def init(opts) do
    state = %{
      members: Keyword.fetch!(opts, :members),
      aggregation: Keyword.get(opts, :aggregation, :majority),
      min_responses: Keyword.get(opts, :min_responses),
      weights: Keyword.get(opts, :weights, equal_weights(length(opts[:members])))
    }

    {:ok, state}
  end

  def handle_call({:predict, input}, _from, state) do
    # Collect predictions from all members
    responses = collect_responses(state.members, input)

    # Check if we have enough responses
    min_required = state.min_responses || div(length(state.members), 2) + 1
    valid_responses = Enum.filter(responses, &match?({:ok, _}, &1))

    if length(valid_responses) >= min_required do
      result = aggregate_responses(valid_responses, state.aggregation, state.weights)
      {:reply, {:ok, result}, state}
    else
      {:reply, {:error, :insufficient_responses}, state}
    end
  end

  defp collect_responses(members, input) do
    members
    |> Task.async_stream(
      fn member ->
        get_prediction(member, input)
      end,
      max_concurrency: length(members),
      timeout: 5000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> {:error, :timeout}
    end)
  end

  defp get_prediction(member, input) when is_function(member, 1) do
    try do
      {:ok, member.(input)}
    rescue
      e -> {:error, e}
    end
  end

  defp get_prediction(member_pid, input) when is_pid(member_pid) do
    try do
      GenServer.call(member_pid, {:predict, input}, 5000)
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp aggregate_responses(responses, :majority, _weights) do
    predictions = Enum.map(responses, fn {:ok, pred} -> pred end)

    predictions
    |> Enum.frequencies()
    |> Enum.max_by(fn {_pred, count} -> count end)
    |> elem(0)
  end

  defp aggregate_responses(responses, :average, weights) do
    predictions = Enum.map(responses, fn {:ok, pred} -> pred end)

    predictions
    |> Enum.zip(weights)
    |> Enum.reduce(0, fn {pred, weight}, acc -> acc + pred * weight end)
  end

  defp aggregate_responses(responses, :weighted, weights) do
    # Weighted voting for categorical outputs
    predictions = Enum.map(responses, fn {:ok, pred} -> pred end)

    predictions
    |> Enum.zip(weights)
    |> Enum.reduce(%{}, fn {pred, weight}, acc ->
      Map.update(acc, pred, weight, &(&1 + weight))
    end)
    |> Enum.max_by(fn {_pred, score} -> score end)
    |> elem(0)
  end

  defp aggregate_responses(responses, custom_fn, _weights) when is_function(custom_fn) do
    predictions = Enum.map(responses, fn {:ok, pred} -> pred end)
    custom_fn.(predictions)
  end

  defp equal_weights(n) do
    weight = 1.0 / n
    List.duplicate(weight, n)
  end
end

defmodule MLFoundation.AgentPatterns.ValidatorAgent do
  @moduledoc """
  Agent for data and model validation.
  Ensures quality and correctness of ML artifacts.
  """
  use GenServer
  require Logger

  def init(opts) do
    state = %{
      schema: Keyword.get(opts, :schema, %{}),
      on_invalid: Keyword.get(opts, :on_invalid, :reject),
      custom_validators: Keyword.get(opts, :custom_validators, []),
      validation_stats: %{valid: 0, invalid: 0}
    }

    {:ok, state}
  end

  def handle_call({:validate, data, _opts}, _from, state) do
    result = perform_validation(data, state.schema, state.custom_validators)

    new_state = update_stats(state, result)

    response =
      case {result, state.on_invalid} do
        {{:ok, _}, _} ->
          result

        {{:error, errors}, :reject} ->
          {:error, errors}

        {{:error, errors}, :fix} ->
          fix_data(data, errors)

        {{:error, errors}, :log} ->
          Logger.warning("Validation errors: #{inspect(errors)}")
          # Pass through with warning
          {:ok, data}
      end

    {:reply, response, new_state}
  end

  defp perform_validation(data, schema, custom_validators) do
    # Basic schema validation
    schema_errors = validate_against_schema(data, schema)

    # Custom validations
    custom_errors =
      Enum.flat_map(custom_validators, fn validator ->
        case validator.(data) do
          :ok -> []
          {:error, error} -> [error]
        end
      end)

    all_errors = schema_errors ++ custom_errors

    if all_errors == [] do
      {:ok, data}
    else
      {:error, all_errors}
    end
  end

  defp validate_against_schema(data, schema) when is_map(schema) do
    Enum.flat_map(schema, fn {key, expected} ->
      case Map.get(data, key) do
        nil -> [{:missing_field, key}]
        value -> validate_value(value, expected, key)
      end
    end)
  end

  defp validate_against_schema(_data, _schema), do: []

  defp validate_value(value, {:type, type}, key) do
    if type_matches?(value, type) do
      []
    else
      [{:type_mismatch, key, expected: type, got: type_of(value)}]
    end
  end

  defp validate_value(value, {:range, {min, max}}, key) do
    if value >= min and value <= max do
      []
    else
      [{:out_of_range, key, value: value, range: {min, max}}]
    end
  end

  defp validate_value(value, {:shape, expected_shape}, key) do
    actual_shape = get_shape(value)

    if shapes_match?(actual_shape, expected_shape) do
      []
    else
      [{:shape_mismatch, key, expected: expected_shape, got: actual_shape}]
    end
  end

  defp validate_value(_value, _expected, _key), do: []

  defp type_matches?(value, type) do
    case type do
      :number -> is_number(value)
      :string -> is_binary(value)
      :list -> is_list(value)
      :map -> is_map(value)
      _ -> true
    end
  end

  defp type_of(value) do
    cond do
      is_number(value) -> :number
      is_binary(value) -> :string
      is_list(value) -> :list
      is_map(value) -> :map
      true -> :unknown
    end
  end

  defp get_shape(value) when is_list(value) do
    {length(value), get_shape(List.first(value) || [])}
  end

  defp get_shape(_value), do: :scalar

  defp shapes_match?({actual_len, actual_inner}, {expected_len, expected_inner}) do
    (expected_len == nil or actual_len == expected_len) and
      shapes_match?(actual_inner, expected_inner)
  end

  defp shapes_match?(actual, expected), do: actual == expected

  defp fix_data(data, errors) do
    # Simple fixing strategy - could be more sophisticated
    fixed =
      Enum.reduce(errors, data, fn error, acc ->
        case error do
          {:missing_field, key} -> Map.put(acc, key, default_value_for(key))
          _ -> acc
        end
      end)

    {:ok, fixed}
  end

  defp default_value_for(_key), do: nil

  defp update_stats(state, {:ok, _}) do
    %{state | validation_stats: %{state.validation_stats | valid: state.validation_stats.valid + 1}}
  end

  defp update_stats(state, {:error, _}) do
    %{
      state
      | validation_stats: %{state.validation_stats | invalid: state.validation_stats.invalid + 1}
    }
  end
end

defmodule MLFoundation.AgentPatterns.TransformerAgent do
  @moduledoc """
  Agent for data transformation.
  Applies configurable transformations to data.
  """
  use GenServer

  def init(opts) do
    state = %{
      transformations: Keyword.get(opts, :transformations, %{}),
      cache_results: Keyword.get(opts, :cache_results, false),
      batch_size: Keyword.get(opts, :batch_size),
      cache: %{}
    }

    {:ok, state}
  end

  def handle_call({:transform, data, name, _opts}, _from, state) do
    case Map.get(state.transformations, name) do
      nil ->
        {:reply, {:error, :unknown_transformation}, state}

      transformation ->
        {result, new_state} = apply_transformation(data, transformation, name, state)
        {:reply, result, new_state}
    end
  end

  defp apply_transformation(data, transformation, name, state) do
    # Check cache if enabled
    cache_key = if state.cache_results, do: {name, hash_data(data)}, else: nil

    case cache_key && Map.get(state.cache, cache_key) do
      nil ->
        # Apply transformation
        result =
          if state.batch_size && is_list(data) do
            apply_batched_transformation(data, transformation, state.batch_size)
          else
            apply_single_transformation(data, transformation)
          end

        # Update cache if enabled
        new_state =
          if cache_key && elem(result, 0) == :ok do
            %{state | cache: Map.put(state.cache, cache_key, result)}
          else
            state
          end

        {result, new_state}

      cached_result ->
        {cached_result, state}
    end
  end

  defp apply_single_transformation(data, transformation) when is_function(transformation, 1) do
    try do
      {:ok, transformation.(data)}
    rescue
      e -> {:error, e}
    end
  end

  defp apply_batched_transformation(data, transformation, batch_size) do
    results =
      data
      |> Enum.chunk_every(batch_size)
      |> Enum.map(fn batch ->
        Enum.map(batch, fn item ->
          case apply_single_transformation(item, transformation) do
            {:ok, result} -> result
            {:error, _} = error -> error
          end
        end)
      end)
      |> List.flatten()

    if Enum.any?(results, &match?({:error, _}, &1)) do
      {:error, :transformation_failed}
    else
      {:ok, results}
    end
  end

  defp hash_data(data) do
    :erlang.phash2(data)
  end
end

defmodule MLFoundation.AgentPatterns.OptimizerAgent do
  @moduledoc """
  Agent for hyperparameter optimization.
  Searches for optimal model configurations.
  """
  use GenServer
  require Logger

  def init(opts) do
    state = %{
      objective_fn: Keyword.fetch!(opts, :objective_fn),
      strategy: Keyword.get(opts, :strategy, :hill_climb),
      max_iterations: Keyword.get(opts, :max_iterations, 100),
      convergence_threshold: Keyword.get(opts, :convergence_threshold, 0.0001),
      history: []
    }

    {:ok, state}
  end

  def handle_call({:optimize, initial}, _from, state) do
    result =
      case state.strategy do
        :hill_climb -> hill_climb_optimize(initial, state)
        :genetic -> genetic_optimize(initial, state)
        :gradient -> gradient_optimize(initial, state)
        custom when is_function(custom) -> custom.(initial, state)
      end

    {:reply, result, %{state | history: []}}
  end

  defp hill_climb_optimize(initial, state) do
    optimize_loop(initial, state.objective_fn.(initial), 0, state, &hill_climb_step/2)
  end

  defp genetic_optimize(initial, state) do
    # Simplified genetic algorithm
    population = generate_population(initial, 20)
    evolve_population(population, 0, state)
  end

  defp gradient_optimize(initial, state) do
    # Simplified gradient descent
    optimize_loop(initial, state.objective_fn.(initial), 0, state, &gradient_step/2)
  end

  defp optimize_loop(current, current_score, iteration, state, step_fn) do
    if iteration >= state.max_iterations do
      {:ok, %{solution: current, score: current_score, iterations: iteration}}
    else
      # Generate next candidate
      candidate = step_fn.(current, state)
      candidate_score = state.objective_fn.(candidate)

      # Check improvement
      improvement = abs(candidate_score - current_score)

      if improvement < state.convergence_threshold do
        {:ok,
         %{solution: candidate, score: candidate_score, iterations: iteration + 1, converged: true}}
      else
        # Continue optimization
        {next, next_score} =
          if candidate_score < current_score do
            {candidate, candidate_score}
          else
            {current, current_score}
          end

        optimize_loop(next, next_score, iteration + 1, state, step_fn)
      end
    end
  end

  defp hill_climb_step(current, _state) do
    # Simple perturbation
    perturb(current, 0.1)
  end

  defp gradient_step(current, state) do
    # Approximate gradient
    gradient = estimate_gradient(current, state.objective_fn)

    # Update with learning rate
    learning_rate = 0.01
    update_with_gradient(current, gradient, learning_rate)
  end

  defp perturb(value, magnitude) when is_number(value) do
    value + (:rand.uniform() - 0.5) * magnitude
  end

  defp perturb(values, magnitude) when is_list(values) do
    Enum.map(values, &perturb(&1, magnitude))
  end

  defp perturb(values, magnitude) when is_map(values) do
    Map.new(values, fn {k, v} -> {k, perturb(v, magnitude)} end)
  end

  defp estimate_gradient(current, objective_fn) when is_number(current) do
    eps = 0.0001
    (objective_fn.(current + eps) - objective_fn.(current - eps)) / (2 * eps)
  end

  defp estimate_gradient(current, objective_fn) when is_list(current) do
    Enum.map(current, &estimate_gradient(&1, objective_fn))
  end

  defp update_with_gradient(current, gradient, lr) when is_number(current) do
    current - lr * gradient
  end

  defp update_with_gradient(current, gradient, lr) when is_list(current) do
    Enum.zip(current, gradient)
    |> Enum.map(fn {val, grad} -> update_with_gradient(val, grad, lr) end)
  end

  defp generate_population(template, size) do
    for _ <- 1..size, do: perturb(template, 0.5)
  end

  defp evolve_population(population, generation, state) do
    if generation >= state.max_iterations do
      best = Enum.min_by(population, &state.objective_fn.(&1))
      {:ok, %{solution: best, score: state.objective_fn.(best), generations: generation}}
    else
      # Evaluate fitness
      scored =
        Enum.map(population, fn individual ->
          {individual, state.objective_fn.(individual)}
        end)
        |> Enum.sort_by(fn {_ind, score} -> score end)

      # Select top performers
      elite_size = div(length(population), 4)
      elite = scored |> Enum.take(elite_size) |> Enum.map(&elem(&1, 0))

      # Create next generation
      next_gen = elite ++ generate_offspring(elite, length(population) - elite_size)

      evolve_population(next_gen, generation + 1, state)
    end
  end

  defp generate_offspring(parents, count) do
    for _ <- 1..count do
      parent = Enum.random(parents)
      perturb(parent, 0.2)
    end
  end
end

defmodule MLFoundation.AgentPatterns.EvaluatorAgent do
  @moduledoc """
  Agent for model evaluation.
  Computes metrics and performance statistics.
  """
  use GenServer

  def init(opts) do
    state = %{
      metrics: Keyword.get(opts, :metrics, []),
      weights: Keyword.get(opts, :weights),
      ranking_strategy: Keyword.get(opts, :ranking_strategy, :score)
    }

    # Normalize weights if provided
    state =
      if state.weights do
        total = Enum.sum(state.weights)
        %{state | weights: Enum.map(state.weights, &(&1 / total))}
      else
        state
      end

    {:ok, state}
  end

  def handle_call({:evaluate, solutions, opts}, _from, state) do
    # Evaluate all solutions
    evaluations =
      Enum.map(solutions, fn solution ->
        scores = evaluate_solution(solution, state.metrics, opts)
        composite = calculate_composite_score(scores, state.weights)

        %{
          solution: solution,
          scores: scores,
          composite_score: composite
        }
      end)

    # Rank solutions
    ranked = rank_solutions(evaluations, state.ranking_strategy)

    {:reply, {:ok, ranked}, state}
  end

  defp evaluate_solution(solution, metrics, opts) do
    ground_truth = Keyword.get(opts, :ground_truth)

    Enum.map(metrics, fn metric ->
      try do
        if ground_truth do
          metric.(solution, ground_truth)
        else
          metric.(solution)
        end
      rescue
        _ -> 0.0
      end
    end)
  end

  defp calculate_composite_score(scores, nil) do
    # Equal weighting
    Enum.sum(scores) / length(scores)
  end

  defp calculate_composite_score(scores, weights) do
    scores
    |> Enum.zip(weights)
    |> Enum.reduce(0, fn {score, weight}, acc -> acc + score * weight end)
  end

  defp rank_solutions(evaluations, :score) do
    Enum.sort_by(evaluations, & &1.composite_score, :desc)
  end

  defp rank_solutions(evaluations, :pareto) do
    # Simple Pareto ranking
    pareto_rank(evaluations, [])
  end

  defp rank_solutions(evaluations, custom_fn) when is_function(custom_fn) do
    custom_fn.(evaluations)
  end

  defp pareto_rank([], ranked), do: Enum.reverse(ranked)

  defp pareto_rank(remaining, ranked) do
    # Find non-dominated solutions
    non_dominated =
      Enum.filter(remaining, fn candidate ->
        not Enum.any?(remaining, fn other ->
          other != candidate and dominates?(other, candidate)
        end)
      end)

    if non_dominated == [] do
      # Fallback to score ranking if no clear dominance
      [best | rest] = Enum.sort_by(remaining, & &1.composite_score, :desc)
      pareto_rank(rest, [best | ranked])
    else
      new_remaining = remaining -- non_dominated
      pareto_rank(new_remaining, non_dominated ++ ranked)
    end
  end

  defp dominates?(solution1, solution2) do
    # Solution1 dominates solution2 if it's better or equal in all metrics
    # and strictly better in at least one
    scores1 = solution1.scores
    scores2 = solution2.scores

    all_better_or_equal =
      Enum.zip(scores1, scores2)
      |> Enum.all?(fn {s1, s2} -> s1 >= s2 end)

    at_least_one_better =
      Enum.zip(scores1, scores2)
      |> Enum.any?(fn {s1, s2} -> s1 > s2 end)

    all_better_or_equal and at_least_one_better
  end
end

defmodule MLFoundation.AgentPatterns.WorkflowCoordinator do
  @moduledoc """
  Coordinator for complex ML workflows.
  Orchestrates multi-stage processing pipelines.
  """
  use GenServer
  require Logger

  def init({agents, config}) do
    state = %{
      agents: agents,
      config: config,
      execution_history: []
    }

    {:ok, state}
  end

  def handle_call({:execute, input}, _from, state) do
    result = execute_workflow(input, state.agents, [])

    new_state = %{
      state
      | execution_history: [{DateTime.utc_now(), result} | state.execution_history]
    }

    {:reply, result, new_state}
  end

  defp execute_workflow(data, [], results) do
    {:ok, data, Enum.reverse(results)}
  end

  defp execute_workflow(data, [{type, agent} | rest], results) do
    case execute_agent_stage(type, agent, data) do
      {:ok, output} ->
        execute_workflow(output, rest, [{type, :success} | results])

      {:error, reason} = error ->
        Logger.error("Workflow stage #{type} failed: #{inspect(reason)}")
        error
    end
  end

  defp execute_agent_stage(type, agent, data) do
    case type do
      :validator -> MLFoundation.AgentPatterns.validate(agent, data)
      :transformer -> MLFoundation.AgentPatterns.transform(agent, data, :default)
      :pipeline -> MLFoundation.AgentPatterns.process_pipeline(agent, data)
      :ensemble -> MLFoundation.AgentPatterns.ensemble_predict(agent, data)
      :optimizer -> MLFoundation.AgentPatterns.optimize(agent, data)
      :evaluator -> MLFoundation.AgentPatterns.evaluate(agent, [data])
      _ -> {:error, :unknown_stage_type}
    end
  end
end
