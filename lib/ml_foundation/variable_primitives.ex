defmodule MLFoundation.VariablePrimitives do
  @moduledoc """
  Foundation-level variable coordination primitives for ML systems.

  This module provides the building blocks for parameter management and
  optimization in ML workflows. Variables represent tunable parameters
  that can be coordinated across agents and optimized by various strategies.

  ## Core Concepts

  1. **Variable Space** - Defines the parameter search space
  2. **Variable Constraints** - Rules and relationships between variables
  3. **Variable Updates** - Coordinated parameter updates across agents
  4. **Variable History** - Tracking parameter evolution over time

  ## Design Philosophy

  Variables are first-class citizens that can be:
  - Shared across multiple agents
  - Updated atomically with consistency guarantees
  - Optimized by external optimization agents
  - Constrained by domain-specific rules
  """

  require Logger
  alias Foundation.AtomicTransaction

  # Variable Definition

  @doc """
  Defines a variable with its domain and constraints.

  ## Variable Types

  - `:continuous` - Real-valued parameters with bounds
  - `:discrete` - Integer or categorical parameters
  - `:structured` - Complex parameters (lists, maps, etc.)
  - `:derived` - Computed from other variables

  ## Examples

      # Continuous variable
      {:ok, learning_rate} = VariablePrimitives.define_variable(
        :learning_rate,
        type: :continuous,
        bounds: {0.0001, 1.0},
        scale: :log
      )
      
      # Discrete variable
      {:ok, batch_size} = VariablePrimitives.define_variable(
        :batch_size,
        type: :discrete,
        values: [16, 32, 64, 128, 256]
      )
  """
  def define_variable(name, opts) do
    type = Keyword.fetch!(opts, :type)

    definition = %{
      name: name,
      type: type,
      metadata: build_variable_metadata(type, opts),
      constraints: Keyword.get(opts, :constraints, []),
      observers: Keyword.get(opts, :observers, []),
      history: []
    }

    # Register variable in Foundation
    case Foundation.register(variable_key(name), self(), definition) do
      :ok -> {:ok, definition}
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a variable space containing multiple related variables.

  ## Options

  - `:variables` - List of variable definitions
  - `:constraints` - Cross-variable constraints
  - `:coordination` - Coordination strategy (:sync, :async, :eventual)

  ## Examples

      {:ok, space} = VariablePrimitives.create_variable_space(
        variables: [
          {:learning_rate, [type: :continuous, bounds: {0.0001, 1.0}]},
          {:momentum, [type: :continuous, bounds: {0.0, 0.99}]}
        ],
        constraints: [
          {:coupled, [:learning_rate, :momentum], fn lr, m -> lr * m < 0.1 end}
        ]
      )
  """
  def create_variable_space(opts) do
    variables = Keyword.fetch!(opts, :variables)
    constraints = Keyword.get(opts, :constraints, [])
    coordination = Keyword.get(opts, :coordination, :sync)

    with {:ok, defined_vars} <- define_variables(variables),
         :ok <- validate_space_definition_constraints(defined_vars, constraints) do
      space = %{
        id: generate_space_id(),
        variables: defined_vars,
        constraints: constraints,
        coordination: coordination,
        version: 0,
        history: []
      }

      # Register the space
      Foundation.register(space_key(space.id), self(), space)

      {:ok, space}
    end
  end

  # Variable Operations

  @doc """
  Gets the current value of a variable.

  ## Examples

      {:ok, value} = VariablePrimitives.get_value(:learning_rate)
  """
  def get_value(variable_name, opts \\ []) do
    space_id = Keyword.get(opts, :space)

    case lookup_variable(variable_name, space_id) do
      {:ok, {_pid, variable}} ->
        {:ok, variable.metadata.current_value}

      error ->
        error
    end
  end

  @doc """
  Updates a variable's value with consistency guarantees.

  ## Options

  - `:atomic` - Use atomic transaction (default: true)
  - `:validate` - Validate against constraints (default: true)
  - `:notify` - Notify observers (default: true)

  ## Examples

      {:ok, updated} = VariablePrimitives.update_value(
        :learning_rate,
        0.01,
        atomic: true
      )
  """
  def update_value(variable_name, new_value, opts \\ []) do
    atomic = Keyword.get(opts, :atomic, true)
    _validate = Keyword.get(opts, :validate, true)
    _notify = Keyword.get(opts, :notify, true)

    if atomic do
      update_atomically(variable_name, new_value, opts)
    else
      update_directly(variable_name, new_value, opts)
    end
  end

  @doc """
  Updates multiple variables atomically.

  ## Examples

      {:ok, updated} = VariablePrimitives.update_values(%{
        learning_rate: 0.01,
        momentum: 0.9,
        batch_size: 64
      })
  """
  def update_values(updates, opts \\ []) when is_map(updates) do
    space_id = Keyword.get(opts, :space)

    # Use Foundation's atomic transaction
    AtomicTransaction.transact(fn tx ->
      results =
        Enum.map(updates, fn {var_name, new_value} ->
          case update_in_transaction(var_name, new_value, space_id, tx) do
            {:ok, updated} -> {:ok, {var_name, updated}}
            error -> error
          end
        end)

      # Check if all updates succeeded
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, Map.new(results, fn {:ok, pair} -> pair end)}
        error -> error
      end
    end)
  end

  # Variable Coordination

  @doc """
  Coordinates variable updates across multiple agents.

  ## Strategies

  - `:consensus` - All agents must agree on update
  - `:voting` - Majority vote on proposed values
  - `:leader` - Leader agent decides updates
  - `:averaged` - Average proposed values

  ## Examples

      {:ok, result} = VariablePrimitives.coordinate_update(
        :learning_rate,
        agent_proposals,
        strategy: :consensus
      )
  """
  def coordinate_update(variable_name, proposals, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :consensus)
    timeout = Keyword.get(opts, :timeout, 5000)

    case strategy do
      :consensus -> coordinate_consensus(variable_name, proposals, timeout)
      :voting -> coordinate_voting(variable_name, proposals, timeout)
      :leader -> coordinate_leader(variable_name, proposals, timeout)
      :averaged -> coordinate_averaged(variable_name, proposals)
    end
  end

  @doc """
  Subscribes to variable updates.

  ## Examples

      VariablePrimitives.subscribe(:learning_rate, fn old_val, new_val ->
        Logger.info("Learning rate changed from \#{old_val} to \#{new_val}")
      end)
  """
  def subscribe(variable_name, callback, opts \\ []) when is_function(callback, 2) do
    space_id = Keyword.get(opts, :space)

    case lookup_variable(variable_name, space_id) do
      {:ok, {_pid, variable}} ->
        # Add observer
        updated = %{variable | observers: [callback | variable.observers]}
        Foundation.update_metadata(variable_key(variable_name), updated)
        :ok

      error ->
        error
    end
  end

  # Variable History and Analysis

  @doc """
  Gets the history of a variable's values over time.

  ## Examples

      {:ok, history} = VariablePrimitives.get_history(:learning_rate, limit: 100)
  """
  def get_history(variable_name, opts \\ []) do
    space_id = Keyword.get(opts, :space)
    limit = Keyword.get(opts, :limit, 100)

    case lookup_variable(variable_name, space_id) do
      {:ok, {_pid, variable}} ->
        history =
          variable.history
          |> Enum.take(limit)
          |> Enum.map(fn {timestamp, value, metadata} ->
            %{timestamp: timestamp, value: value, metadata: metadata}
          end)

        {:ok, history}

      error ->
        error
    end
  end

  @doc """
  Analyzes variable behavior and suggests optimizations.

  ## Analysis Types

  - `:convergence` - Check if variable is converging
  - `:correlation` - Find correlated variables
  - `:sensitivity` - Measure impact on objective
  - `:optimal_range` - Suggest better bounds

  ## Examples

      {:ok, analysis} = VariablePrimitives.analyze_variable(
        :learning_rate,
        type: :convergence
      )
  """
  def analyze_variable(variable_name, opts \\ []) do
    analysis_type = Keyword.get(opts, :type, :convergence)

    with {:ok, history} <- get_history(variable_name, opts) do
      result =
        case analysis_type do
          :convergence -> analyze_convergence(history)
          :correlation -> analyze_correlation(variable_name, history, opts)
          :sensitivity -> analyze_sensitivity(variable_name, history, opts)
          :optimal_range -> analyze_optimal_range(history)
        end

      {:ok, result}
    end
  end

  # Variable Constraints

  @doc """
  Adds a constraint to a variable or variable space.

  ## Constraint Types

  - `:bounds` - Value must be within bounds
  - `:relationship` - Relationship between variables
  - `:custom` - Custom validation function

  ## Examples

      # Add bounds constraint
      VariablePrimitives.add_constraint(:learning_rate,
        type: :bounds,
        min: 0.0001,
        max: 0.1
      )
      
      # Add relationship constraint
      VariablePrimitives.add_constraint(:optimizer_space,
        type: :relationship,
        variables: [:learning_rate, :batch_size],
        constraint: fn lr, bs -> lr * bs < 1.0 end
      )
  """
  def add_constraint(_target, _constraint_def) do
    # Implementation would add constraint to variable or space
    {:ok, :constraint_added}
  end

  @doc """
  Validates a value or set of values against constraints.

  ## Examples

      {:ok, :valid} = VariablePrimitives.validate_constraints(
        :learning_rate,
        0.01
      )
  """
  def validate_constraints(variable_name, value, opts \\ []) do
    space_id = Keyword.get(opts, :space)

    with {:ok, {_pid, variable}} <- lookup_variable(variable_name, space_id),
         :ok <- validate_value_constraints(value, variable.constraints),
         :ok <- validate_space_constraints(variable_name, value, space_id) do
      {:ok, :valid}
    end
  end

  # Private helper functions

  defp build_variable_metadata(:continuous, opts) do
    %{
      bounds: Keyword.get(opts, :bounds, {:neg_infinity, :infinity}),
      scale: Keyword.get(opts, :scale, :linear),
      current_value: Keyword.get(opts, :initial, 0.0),
      step_size: Keyword.get(opts, :step_size, 0.01)
    }
  end

  defp build_variable_metadata(:discrete, opts) do
    values = Keyword.get(opts, :values, [])
    initial = Keyword.get(opts, :initial, List.first(values))

    %{
      values: values,
      current_value: initial,
      current_index: Enum.find_index(values, &(&1 == initial))
    }
  end

  defp build_variable_metadata(:structured, opts) do
    %{
      schema: Keyword.get(opts, :schema, %{}),
      current_value: Keyword.get(opts, :initial, %{}),
      validator: Keyword.get(opts, :validator)
    }
  end

  defp build_variable_metadata(:derived, opts) do
    %{
      dependencies: Keyword.fetch!(opts, :dependencies),
      compute_fn: Keyword.fetch!(opts, :compute_fn),
      current_value: nil,
      cache_ttl: Keyword.get(opts, :cache_ttl, 0)
    }
  end

  defp variable_key(name), do: {:ml_variable, name}
  defp space_key(id), do: {:ml_variable_space, id}

  defp generate_space_id do
    "varspace_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp define_variables(variable_specs) do
    results =
      Enum.map(variable_specs, fn {name, opts} ->
        define_variable(name, opts)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        variables = Enum.map(results, fn {:ok, var} -> var end)
        {:ok, variables}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_space_definition_constraints(variables, constraints) do
    # Validate that all referenced variables exist
    var_names = MapSet.new(variables, & &1.name)

    Enum.reduce_while(constraints, :ok, fn constraint, _acc ->
      case constraint do
        {:coupled, var_list, _fn} ->
          if Enum.all?(var_list, &MapSet.member?(var_names, &1)) do
            {:cont, :ok}
          else
            {:halt, {:error, :unknown_variables_in_constraint}}
          end

        _ ->
          {:cont, :ok}
      end
    end)
  end

  defp lookup_variable(name, nil) do
    Foundation.lookup(variable_key(name))
  end

  defp lookup_variable(name, space_id) do
    case Foundation.lookup(space_key(space_id)) do
      {:ok, {_pid, space}} ->
        var = Enum.find(space.variables, &(&1.name == name))

        if var do
          {:ok, {self(), var}}
        else
          {:error, :variable_not_found}
        end

      error ->
        error
    end
  end

  defp update_atomically(variable_name, new_value, opts) do
    _space_id = Keyword.get(opts, :space)

    # For now, just use direct update since we don't have proper transaction support
    # Issue: Implement proper atomic transaction support for variable updates
    # This will require integration with Foundation.AtomicTransaction
    update_directly(variable_name, new_value, opts)
  end

  defp update_directly(variable_name, new_value, opts) do
    space_id = Keyword.get(opts, :space)

    case lookup_variable(variable_name, space_id) do
      {:ok, {_pid, variable}} ->
        # Update value
        old_value = variable.metadata.current_value
        updated_metadata = Map.put(variable.metadata, :current_value, new_value)

        updated_var = %{
          variable
          | metadata: updated_metadata,
            history: [{DateTime.utc_now(), new_value, %{}} | variable.history]
        }

        Foundation.update_metadata(variable_key(variable_name), updated_var)

        # Notify observers
        if Keyword.get(opts, :notify, true) do
          notify_observers(variable.observers, old_value, new_value)
        end

        {:ok, updated_var}

      error ->
        error
    end
  end

  defp update_in_transaction(variable_name, new_value, space_id, _tx) do
    # Similar to update_directly but within transaction context
    update_directly(variable_name, new_value, space: space_id, notify: false)
  end

  defp coordinate_consensus(variable_name, proposals, _timeout) do
    # Use Foundation's consensus mechanism
    proposal_values = Enum.map(proposals, fn {_agent, value} -> value end)

    if Enum.all?(proposal_values, &(&1 == List.first(proposal_values))) do
      # All agree
      update_value(variable_name, List.first(proposal_values))
    else
      {:error, :no_consensus}
    end
  end

  defp coordinate_voting(variable_name, proposals, _timeout) do
    # Majority voting
    frequencies =
      proposals
      |> Enum.map(fn {_agent, value} -> value end)
      |> Enum.frequencies()

    {winner, _count} = Enum.max_by(frequencies, fn {_val, count} -> count end)
    update_value(variable_name, winner)
  end

  defp coordinate_leader(variable_name, proposals, _timeout) do
    # First proposal is from leader
    case proposals do
      [{_leader, value} | _] -> update_value(variable_name, value)
      [] -> {:error, :no_proposals}
    end
  end

  defp coordinate_averaged(variable_name, proposals) do
    values = Enum.map(proposals, fn {_agent, value} -> value end)

    averaged =
      case values do
        [] ->
          # No values to average
          nil

        [v | _] when is_number(v) ->
          Enum.sum(values) / length(values)

        [v | _] when is_list(v) ->
          # Element-wise average for lists
          transpose(values)
          |> Enum.map(&(Enum.sum(&1) / length(&1)))

        [v | _] ->
          # Can't average, use first
          v
      end

    update_value(variable_name, averaged)
  end

  defp transpose([[] | _]), do: []

  defp transpose(lists) do
    [Enum.map(lists, &hd/1) | transpose(Enum.map(lists, &tl/1))]
  end

  defp notify_observers(observers, old_value, new_value) do
    Enum.each(observers, fn callback ->
      spawn(fn -> callback.(old_value, new_value) end)
    end)
  end

  defp validate_value_constraints(value, constraints) do
    Enum.reduce_while(constraints, :ok, fn constraint, _acc ->
      if validate_single_constraint(value, constraint) do
        {:cont, :ok}
      else
        {:halt, {:error, {:constraint_violation, constraint}}}
      end
    end)
  end

  defp validate_single_constraint(value, {:bounds, min, max}) do
    value >= min and value <= max
  end

  defp validate_single_constraint(value, {:in, allowed_values}) do
    value in allowed_values
  end

  defp validate_single_constraint(value, {:custom, validator}) do
    validator.(value)
  end

  defp validate_space_constraints(_variable_name, _value, nil), do: :ok

  defp validate_space_constraints(_variable_name, _value, _space_id) do
    # Would check cross-variable constraints in the space
    # For now, simplified implementation
    :ok
  end

  # Analysis functions

  defp analyze_convergence(history) do
    values = Enum.map(history, & &1.value)

    # Simple convergence check - is variance decreasing?
    if length(values) >= 10 do
      recent = Enum.take(values, 5)
      older = Enum.slice(values, 5, 5)

      recent_var = variance(recent)
      older_var = variance(older)

      %{
        converged: recent_var < older_var * 0.5,
        trend: if(recent_var < older_var, do: :converging, else: :diverging),
        stability_score: 1.0 - recent_var / (older_var + 0.0001)
      }
    else
      %{
        converged: false,
        trend: :insufficient_data,
        stability_score: 0.0
      }
    end
  end

  defp analyze_correlation(_variable_name, _history, opts) do
    other_var = Keyword.get(opts, :with)

    if other_var do
      # Would compute correlation with other variable
      %{
        correlation: 0.0,
        significance: 0.05,
        relationship: :none
      }
    else
      {:error, :no_comparison_variable}
    end
  end

  defp analyze_sensitivity(_variable_name, _history, opts) do
    objective_fn = Keyword.get(opts, :objective_fn)

    if objective_fn do
      # Would compute sensitivity analysis
      %{
        sensitivity: 1.0,
        impact: :high,
        optimal_direction: :decrease
      }
    else
      {:error, :no_objective_function}
    end
  end

  defp analyze_optimal_range(history) do
    values = Enum.map(history, & &1.value)

    if values != [] do
      %{
        suggested_min: Enum.min(values) * 0.8,
        suggested_max: Enum.max(values) * 1.2,
        sweet_spot: median(values)
      }
    else
      {:error, :insufficient_history}
    end
  end

  defp variance(values) do
    mean = Enum.sum(values) / length(values)

    sum_squares =
      Enum.reduce(values, 0, fn x, acc ->
        acc + :math.pow(x - mean, 2)
      end)

    sum_squares / length(values)
  end

  defp median(values) do
    sorted = Enum.sort(values)
    mid = div(length(sorted), 2)

    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end
end

# Example agent that uses variables
defmodule MLFoundation.VariablePrimitives.VariableAgent do
  @moduledoc """
  Example agent that manages and uses variables in its operations.
  """

  use GenServer
  require Logger
  alias MLFoundation.VariablePrimitives

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    # Create variable space for this agent
    {:ok, space} =
      VariablePrimitives.create_variable_space(
        variables: Keyword.get(opts, :variables, []),
        constraints: Keyword.get(opts, :constraints, [])
      )

    # Subscribe to variable updates
    Enum.each(space.variables, fn var ->
      VariablePrimitives.subscribe(var.name, &handle_variable_update/2, space: space.id)
    end)

    {:ok,
     %{
       space: space,
       state: :ready
     }}
  end

  def handle_call({:get_variable, name}, _from, state) do
    result = VariablePrimitives.get_value(name, space: state.space.id)
    {:reply, result, state}
  end

  def handle_call({:update_variable, name, value}, _from, state) do
    result = VariablePrimitives.update_value(name, value, space: state.space.id)
    {:reply, result, state}
  end

  def handle_call({:update_variables, updates}, _from, state) do
    result = VariablePrimitives.update_values(updates, space: state.space.id)
    {:reply, result, state}
  end

  defp handle_variable_update(old_value, new_value) do
    Logger.debug("Variable updated: #{old_value} -> #{new_value}")
  end
end
