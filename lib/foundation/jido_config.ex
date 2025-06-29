defmodule Foundation.JidoConfig do
  @moduledoc """
  Hierarchical configuration system for Jido action execution log levels.

  Provides a smart configuration hierarchy:
  1. **Invocation-level** (highest priority) - passed directly to run/exec calls
  2. **File-level** (module-level) - configured per module
  3. **App-wide** (lowest priority) - global default from application config

  ## Configuration Hierarchy

  ```
  Invocation-level (opts)
       ↓ (if not set)
  File-level (module config)
       ↓ (if not set)
  App-wide (application config)
       ↓ (if not set)
  Default (:warning)
  ```

  ## Usage

  ### App-wide Configuration
  ```elixir
  # config/config.exs
  config :foundation,
    jido_log_level: :warning  # Global default for all Jido actions
  ```

  ### File-level Configuration
  ```elixir
  defmodule MyAgent do
    use Foundation.JidoConfig, log_level: :error  # Override for this module

    def run_action do
      # Will use :error level unless overridden
      JidoHelper.run_with_config(action, params, context)
    end
  end
  ```

  ### Invocation-level Configuration
  ```elixir
  # Highest priority - overrides everything
  JidoHelper.run_with_config(action, params, context, log_level: :debug)
  ```
  """

  @default_log_level :warning

  # --- Module Usage Macro ---

  @doc """
  Provides Jido configuration for a module.

  ## Options
  - `:log_level` - Default log level for all Jido operations in this module

  ## Example
  ```elixir
  defmodule MyAgent do
    use Foundation.JidoConfig, log_level: :error

    def some_action do
      # Will use :error level by default
      JidoHelper.run_with_config(action, params, context)
    end
  end
  ```
  """
  defmacro __using__(opts \\ []) do
    module_log_level = Keyword.get(opts, :log_level)

    quote do
      @jido_module_log_level unquote(module_log_level)

      def __jido_module_log_level__, do: @jido_module_log_level

      # Import the helper functions
      import Foundation.JidoConfig.Helpers
    end
  end

  # --- Configuration Resolution ---

  @doc """
  Resolves the log level using the hierarchical configuration system.

  ## Parameters
  - `module` - The calling module (for file-level config)
  - `opts` - Invocation options (highest priority)

  ## Returns
  The resolved log level atom
  """
  def resolve_log_level(module \\ nil, opts \\ []) do
    # 1. Invocation-level (highest priority)
    case Keyword.get(opts, :log_level) do
      nil ->
        # 2. File-level (module config)
        case get_module_log_level(module) do
          nil ->
            # 3. App-wide (application config)
            case get_app_log_level() do
              nil ->
                # 4. Default
                @default_log_level

              app_level ->
                app_level
            end

          module_level ->
            module_level
        end

      invocation_level ->
        invocation_level
    end
  end

  @doc """
  Gets the module-level log level configuration.
  """
  def get_module_log_level(nil), do: nil

  def get_module_log_level(module) do
    if function_exported?(module, :__jido_module_log_level__, 0) do
      module.__jido_module_log_level__()
    else
      nil
    end
  end

  @doc """
  Gets the app-wide log level configuration.
  """
  def get_app_log_level do
    Application.get_env(:foundation, :jido_log_level)
  end

  @doc """
  Merges log level into opts using hierarchical resolution.

  ## Parameters
  - `module` - The calling module
  - `opts` - Existing options keyword list

  ## Returns
  Updated opts with log_level set according to hierarchy
  """
  def merge_log_level(module, opts \\ []) do
    current_log_level = Keyword.get(opts, :log_level)

    if current_log_level do
      # Already has invocation-level config, don't override
      opts
    else
      # Resolve from hierarchy and merge
      resolved_level = resolve_log_level(module, opts)
      Keyword.put(opts, :log_level, resolved_level)
    end
  end
end
