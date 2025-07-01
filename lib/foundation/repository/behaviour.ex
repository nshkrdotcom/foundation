defmodule Foundation.Repository.Behaviour do
  @moduledoc """
  Behaviour definition for Foundation repositories.

  Defines the contract that all repositories must implement.
  """

  @callback insert(key :: term(), value :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback get(key :: term(), opts :: keyword()) ::
              {:ok, map()} | {:error, :not_found}

  @callback update(key :: term(), updates :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback delete(key :: term(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback all(opts :: keyword()) ::
              {:ok, [map()]}

  @callback query() :: Foundation.Repository.Query.t()

  @callback transaction((-> any())) ::
              {:ok, any()} | {:error, term()}
end
