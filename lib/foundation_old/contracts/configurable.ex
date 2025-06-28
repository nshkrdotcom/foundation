defmodule Foundation.Contracts.Configurable do
  @moduledoc """
  Behaviour contract for configuration providers.

  Defines the interface that all configuration implementations must follow.
  Ensures consistent API across different configuration backends.
  """

  alias Foundation.Types.{Config, Error}

  @type config_path :: [atom()]
  @type config_value :: term()

  @doc """
  Get the complete configuration.
  """
  @callback get() :: {:ok, Config.t()} | {:error, Error.t()}

  @doc """
  Get a configuration value by path.
  """
  @callback get(config_path()) :: {:ok, config_value()} | {:error, Error.t()}

  @doc """
  Update a configuration value at the given path.
  """
  @callback update(config_path(), config_value()) :: :ok | {:error, Error.t()}

  @doc """
  Validate a configuration structure.
  """
  @callback validate(Config.t()) :: :ok | {:error, Error.t()}

  @doc """
  Get the list of paths that can be updated at runtime.
  """
  @callback updatable_paths() :: [config_path()]

  @doc """
  Reset configuration to defaults.
  """
  @callback reset() :: :ok | {:error, Error.t()}

  @doc """
  Check if the configuration service is available.
  """
  @callback available?() :: boolean()
end
