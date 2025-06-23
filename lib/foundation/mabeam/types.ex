defmodule Foundation.MABEAM.Types do
  @moduledoc """
  Core data structures for Foundation MABEAM.

  This module defines all serializable, distribution-ready types.
  Every type avoids non-serializable terms (PIDs, functions, references).

  ## Design Philosophy

  - 100% serializable data structures
  - Distribution-ready architecture
  - Conflict resolution strategies for variables
  - Agent configuration with restart policies
  - Coordination request/response patterns
  """

  @type agent_id :: atom() | String.t()
  @type process_reference :: {:agent, agent_id()}

  @type agent_type ::
          :coordinator | :worker | :monitor | :resource_provider | :optimizer

  @type restart_policy :: %{
          strategy: :permanent | :temporary | :transient,
          max_restarts: non_neg_integer(),
          period_seconds: pos_integer(),
          backoff_strategy: :linear | :exponential | :fixed
        }

  @type resource_spec :: %{
          memory_mb: pos_integer(),
          cpu_weight: float(),
          network_priority: :low | :normal | :high,
          custom_resources: map()
        }

  @type agent_config :: %{
          id: agent_id(),
          module: module(),
          args: [term()],
          type: agent_type(),
          capabilities: [atom()],
          restart_policy: restart_policy(),
          resource_requirements: resource_spec(),
          metadata: map(),
          created_at: DateTime.t()
        }

  @type conflict_resolution_strategy ::
          :last_write_wins | :consensus | :priority_based | {:custom, module(), atom()}

  @type access_permissions ::
          :public | :restricted | {:agents, [agent_id()]} | {:capabilities, [atom()]}

  @type universal_variable :: %{
          name: atom(),
          value: term(),
          version: pos_integer(),
          last_modifier: agent_id(),
          conflict_resolution: conflict_resolution_strategy(),
          access_permissions: access_permissions(),
          metadata: map(),
          constraints: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type request_type ::
          :consensus | :negotiation | :auction | :market | :resource_allocation

  @type response_type ::
          :success | :failure | :timeout | :partial

  @type coordination_request :: %{
          protocol: atom(),
          type: request_type(),
          params: map(),
          timeout: pos_integer(),
          correlation_id: binary(),
          created_at: DateTime.t()
        }

  @type coordination_response :: %{
          correlation_id: binary(),
          response_type: response_type(),
          data: term(),
          confidence: float(),
          metadata: map()
        }

  @type auction_spec :: %{
          type: atom(),
          resource_id: term(),
          participants: [agent_id()],
          starting_price: number() | nil,
          payment_rule: atom(),
          auction_params: map(),
          created_at: DateTime.t()
        }

  # Agent Config Functions

  @spec new_agent_config(agent_id(), module(), list()) :: agent_config()
  def new_agent_config(id, module, args) do
    new_agent_config(id, module, args, [])
  end

  @spec new_agent_config(agent_id(), module(), [term()], keyword()) :: agent_config()
  def new_agent_config(id, module, args, opts) do
    %{
      id: id,
      module: module,
      args: args,
      type: Keyword.get(opts, :type, :worker),
      capabilities: Keyword.get(opts, :capabilities, []),
      restart_policy:
        Keyword.get(opts, :restart_policy, %{
          strategy: :permanent,
          max_restarts: 3,
          period_seconds: 60,
          backoff_strategy: :exponential
        }),
      resource_requirements:
        Keyword.get(opts, :resource_requirements, %{
          memory_mb: 64,
          cpu_weight: 1.0,
          network_priority: :normal,
          custom_resources: %{}
        }),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now()
    }
  end

  @spec validate_agent_config(agent_config()) :: {:ok, agent_config()} | {:error, term()}
  def validate_agent_config(config) when is_map(config) do
    with {:ok, _} <- validate_agent_id(config[:id]),
         {:ok, _} <- validate_module(config[:module]),
         {:ok, _} <- validate_args(config[:args]),
         {:ok, _} <- validate_capabilities(config[:capabilities]) do
      {:ok, config}
    else
      error -> error
    end
  end

  def validate_agent_config(_), do: {:error, {:invalid_config, "must be a map"}}

  defp validate_agent_id(id) when is_atom(id) and not is_nil(id), do: {:ok, id}
  defp validate_agent_id(_), do: {:error, {:invalid_agent_id, "must be a non-nil atom"}}

  defp validate_module(module) when is_atom(module), do: {:ok, module}
  defp validate_module(_), do: {:error, {:invalid_module, "must be an atom"}}

  defp validate_args(args) when is_list(args), do: {:ok, args}
  defp validate_args(_), do: {:error, {:invalid_args, "must be a list"}}

  defp validate_capabilities(caps) when is_list(caps), do: {:ok, caps}
  defp validate_capabilities(_), do: {:error, {:invalid_capabilities, "must be a list"}}

  # Universal Variable Functions

  @spec new_variable(atom(), term(), agent_id()) :: universal_variable()
  def new_variable(name, value, modifier) do
    new_variable(name, value, modifier, [])
  end

  @spec new_variable(atom(), term(), agent_id(), keyword()) :: universal_variable()
  def new_variable(name, value, modifier, opts) do
    now = DateTime.utc_now()

    %{
      name: name,
      value: value,
      version: 1,
      last_modifier: modifier,
      conflict_resolution: Keyword.get(opts, :conflict_resolution, :last_write_wins),
      access_permissions: Keyword.get(opts, :access_permissions, :public),
      metadata: Keyword.get(opts, :metadata, %{}),
      constraints: Keyword.get(opts, :constraints, %{}),
      created_at: now,
      updated_at: now
    }
  end

  @spec validate_variable(universal_variable()) :: {:ok, universal_variable()} | {:error, term()}
  def validate_variable(var) when is_map(var) do
    with {:ok, _} <- validate_variable_name(var[:name]),
         {:ok, _} <- validate_version(var[:version]) do
      {:ok, var}
    else
      error -> error
    end
  end

  def validate_variable(_), do: {:error, {:invalid_variable, "must be a map"}}

  defp validate_variable_name(name) when is_atom(name) and not is_nil(name), do: {:ok, name}
  defp validate_variable_name(_), do: {:error, {:invalid_variable_name, "must be a non-nil atom"}}

  defp validate_version(version) when is_integer(version) and version > 0, do: {:ok, version}
  defp validate_version(_), do: {:error, {:invalid_version, "must be a positive integer"}}

  # Coordination Request Functions

  @spec new_coordination_request(atom(), request_type(), map(), keyword()) :: coordination_request()
  def new_coordination_request(protocol, type, params, opts \\ []) do
    %{
      protocol: protocol,
      type: type,
      params: params,
      timeout: Keyword.get(opts, :timeout, 5000),
      correlation_id: generate_correlation_id(),
      created_at: DateTime.utc_now()
    }
  end

  @spec validate_coordination_request(coordination_request()) ::
          {:ok, coordination_request()} | {:error, term()}
  def validate_coordination_request(request) when is_map(request) do
    with {:ok, _} <- validate_protocol(request[:protocol]),
         {:ok, _} <- validate_request_type(request[:type]),
         {:ok, _} <- validate_params(request[:params]) do
      {:ok, request}
    else
      error -> error
    end
  end

  def validate_coordination_request(_), do: {:error, {:invalid_request, "must be a map"}}

  defp validate_protocol(protocol) when is_atom(protocol), do: {:ok, protocol}
  defp validate_protocol(_), do: {:error, {:invalid_protocol, "must be an atom"}}

  defp validate_request_type(type) when is_atom(type), do: {:ok, type}
  defp validate_request_type(_), do: {:error, {:invalid_request_type, "must be an atom"}}

  defp validate_params(params) when is_map(params), do: {:ok, params}
  defp validate_params(_), do: {:error, {:invalid_params, "must be a map"}}

  # Auction Spec Functions

  @spec new_auction_spec(atom(), term(), [agent_id()]) :: auction_spec()
  def new_auction_spec(type, resource_id, participants) do
    new_auction_spec(type, resource_id, participants, [])
  end

  @spec new_auction_spec(atom(), term(), [agent_id()], keyword()) :: auction_spec()
  def new_auction_spec(type, resource_id, participants, opts) do
    auction_params =
      case type do
        :english ->
          %{
            increment: Keyword.get(opts, :increment),
            max_rounds: Keyword.get(opts, :max_rounds)
          }

        :dutch ->
          %{
            decrement: Keyword.get(opts, :decrement),
            min_price: Keyword.get(opts, :min_price)
          }

        _ ->
          %{}
      end

    %{
      type: type,
      resource_id: resource_id,
      participants: participants,
      starting_price: Keyword.get(opts, :starting_price),
      payment_rule: Keyword.get(opts, :payment_rule, :first_price),
      auction_params: auction_params,
      created_at: DateTime.utc_now()
    }
  end

  @spec validate_auction_spec(auction_spec()) :: {:ok, auction_spec()} | {:error, term()}
  def validate_auction_spec(spec) when is_map(spec) do
    with {:ok, _} <- validate_auction_type(spec[:type]),
         {:ok, _} <- validate_participants(spec[:participants]) do
      {:ok, spec}
    else
      error -> error
    end
  end

  def validate_auction_spec(_), do: {:error, {:invalid_auction_spec, "must be a map"}}

  defp validate_auction_type(type) when type in [:sealed_bid, :english, :dutch], do: {:ok, type}

  defp validate_auction_type(_),
    do: {:error, {:invalid_auction_type, "must be :sealed_bid, :english, or :dutch"}}

  defp validate_participants([]),
    do: {:error, {:no_participants, "must have at least one participant"}}

  defp validate_participants(participants) when is_list(participants), do: {:ok, participants}
  defp validate_participants(_), do: {:error, {:invalid_participants, "must be a list"}}

  # Utility Functions

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end
