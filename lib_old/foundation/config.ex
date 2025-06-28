defmodule Foundation.Config do
  @moduledoc """
  Public API for configuration management.

  Thin wrapper around ConfigServer that provides a clean, documented interface.
  All business logic is delegated to the service layer.
  """

  @behaviour Foundation.Contracts.Configurable

  alias Foundation.Error
  alias Foundation.Services.ConfigServer
  alias Foundation.Types.Config

  @type config_path :: [atom()]
  @type config_value :: term()

  @forbidden_update_paths [
    [:ai, :api_key],
    [:storage, :encryption_key],
    [:security],
    [:system, :node_name]
  ]

  @doc """
  Initialize the configuration service.

  ## Examples

      iex> Foundation.Config.initialize()
      :ok
  """
  @spec initialize() :: :ok | {:error, Error.t()}
  def initialize do
    ConfigServer.initialize()
  end

  @doc """
  Initialize the configuration service with options.

  ## Examples

      iex> Foundation.Config.initialize(cache_size: 1000)
      :ok
  """
  @spec initialize(keyword()) :: :ok | {:error, Error.t()}
  def initialize(opts) when is_list(opts) do
    ConfigServer.initialize(opts)
  end

  @doc """
  Get configuration service status.

  ## Examples

      iex> Foundation.Config.status()
      {:ok, %{status: :running, uptime: 12_345}}
  """
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    ConfigServer.status()
  end

  @doc """
  Get the complete configuration.

  ## Examples

      iex> Foundation.Config.get()
      {:ok, %Config{...}}
  """
  @spec get() :: {:ok, Config.t()} | {:error, Error.t()}
  defdelegate get(), to: ConfigServer

  @doc """
  Get a configuration value by path.

  ## Examples

      iex> Foundation.Config.get([:ai, :provider])
      {:ok, :openai}

      iex> Foundation.Config.get([:nonexistent, :path])
      {:error, %Error{error_type: :config_path_not_found}}
  """
  @spec get(config_path()) :: {:ok, config_value()} | {:error, Error.t()}
  defdelegate get(path), to: ConfigServer

  @doc """
  Update a configuration value at the given path.

  Only paths returned by `updatable_paths/0` can be updated at runtime.

  ## Examples

      iex> Foundation.Config.update([:dev, :debug_mode], true)
      :ok

      iex> Foundation.Config.update([:ai, :provider], :anthropic)
      {:error, %Error{error_type: :config_update_forbidden}}
  """
  @spec update(config_path(), config_value()) :: :ok | {:error, Error.t()}
  defdelegate update(path, value), to: ConfigServer

  @doc """
  Validate a configuration structure.

  ## Examples

      iex> config = %Config{ai: %{provider: :invalid}}
      iex> Foundation.Config.validate(config)
      {:error, %Error{error_type: :invalid_config_value}}
  """
  @spec validate(Config.t()) :: :ok | {:error, Error.t()}
  defdelegate validate(config), to: ConfigServer

  @doc """
  Get the list of paths that can be updated at runtime.

  ## Examples

      iex> Foundation.Config.updatable_paths()
      [
        [:ai, :planning, :sampling_rate],
        [:dev, :debug_mode],
        ...
      ]
  """
  @spec updatable_paths() :: [[atom(), ...], ...]
  defdelegate updatable_paths(), to: ConfigServer

  @doc """
  Reset configuration to defaults.

  ## Examples

      iex> Foundation.Config.reset()
      :ok
  """
  @spec reset() :: :ok | {:error, Error.t()}
  defdelegate reset(), to: ConfigServer

  @doc """
  Check if the configuration service is available.

  ## Examples

      iex> Foundation.Config.available?()
      true
  """
  @spec available?() :: boolean()
  defdelegate available?(), to: ConfigServer

  @doc """
  Subscribe to configuration change notifications.

  The calling process will receive messages of the form:
  `{:config_notification, {:config_updated, path, new_value}}`

  ## Examples

      iex> Foundation.Config.subscribe()
      :ok
  """
  @spec subscribe() :: :ok | {:error, Error.t()}
  def subscribe do
    ConfigServer.subscribe()
  end

  @doc """
  Unsubscribe from configuration change notifications.

  ## Examples

      iex> Foundation.Config.unsubscribe()
      :ok
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    ConfigServer.unsubscribe()
  end

  @doc """
  Get configuration with a default value if path doesn't exist.

  ## Examples

      iex> Foundation.Config.get_with_default([:ai, :timeout], 30_000)
      30_000
  """
  @spec get_with_default(config_path(), config_value()) :: config_value()
  # Dialyzer warning suppressed: Config.get/1 may never fail in current context,
  # but this graceful fallback pattern is intentional for robustness
  @dialyzer {:nowarn_function, get_with_default: 2}
  def get_with_default(path, default) do
    case get(path) do
      {:ok, value} -> value
      {:error, _} -> default
    end
  end

  @doc """
  Update configuration if the path is updatable, otherwise return error.

  Convenience function that checks updatable paths before attempting update.

  ## Examples

      iex> Foundation.Config.safe_update([:dev, :debug_mode], true)
      :ok
  """
  @spec safe_update(config_path(), config_value()) :: :ok | {:error, Error.t()}
  def safe_update(path, value) do
    cond do
      not is_list(path) ->
        {:error, Error.new(:invalid_path, "Invalid configuration path")}

      path in @forbidden_update_paths ->
        {:error, Error.new(:config_update_forbidden, "Configuration path update forbidden")}

      true ->
        update(path, value)
    end
  end
end
