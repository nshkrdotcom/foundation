defmodule Foundation.Logic.ConfigLogic do
  @moduledoc """
  Pure business logic functions for configuration operations.

  Contains configuration manipulation, merging, and transformation logic.
  No side effects - all functions are pure and easily testable.
  """

  alias Foundation.Types.{Config, Error}
  alias Foundation.Validation.ConfigValidator
  require Logger

  @type config_path :: [atom()]
  @type config_value :: term()

  # Paths that can be updated at runtime
  @updatable_paths [
    [:ai, :planning, :sampling_rate],
    [:ai, :planning, :performance_target],
    [:capture, :processing, :batch_size],
    [:capture, :processing, :flush_interval],
    [:interface, :query_timeout],
    [:interface, :max_results],
    [:dev, :debug_mode],
    [:dev, :verbose_logging],
    [:dev, :performance_monitoring],
    [:infrastructure, :rate_limiting, :enabled],
    [:infrastructure, :circuit_breaker, :enabled],
    [:infrastructure, :connection_pool, :enabled],
    [:infrastructure, :rate_limiting, :cleanup_interval]
  ]

  @doc """
  Get the list of paths that can be updated at runtime.
  """
  @spec updatable_paths() :: [[atom(), ...], ...]
  def updatable_paths, do: @updatable_paths

  @doc """
  Check if a configuration path can be updated at runtime.
  """
  @spec updatable_path?(config_path()) :: boolean()
  def updatable_path?(path) when is_list(path) do
    path in @updatable_paths
  end

  @doc """
  Update a configuration value at the given path.
  Returns the updated configuration if successful.
  """
  @spec update_config(Config.t(), config_path(), config_value()) ::
          {:ok, Config.t()} | {:error, Error.t()}
  def update_config(%Config{} = config, path, value) when is_list(path) do
    cond do
      not validate_path_security(path) ->
        {:error,
         Error.new(
           code: 1000,
           error_type: :security_violation,
           message:
             "Configuration path contains potentially malicious components: #{inspect(path)}",
           context: %{path: path, reason: :malicious_path},
           category: :config,
           subcategory: :security,
           severity: :high
         )}

      not validate_value_security(value) ->
        {:error,
         Error.new(
           code: 1005,
           error_type: :security_violation,
           message: "Configuration value contains potentially dangerous content",
           context: %{value_type: get_value_type(value), reason: :dangerous_value},
           category: :config,
           subcategory: :security,
           severity: :high
         )}

      not updatable_path?(path) ->
        create_error(
          :config_update_forbidden,
          "Configuration path #{inspect(path)} cannot be updated at runtime",
          %{path: path, allowed_paths: @updatable_paths}
        )

      true ->
        new_config = put_in(config, path, value)

        case ConfigValidator.validate(new_config) do
          :ok -> {:ok, new_config}
          {:error, _} = error -> error
        end
    end
  end

  @doc """
  Get a configuration value by path.
  """
  @spec get_config_value(Config.t(), config_path()) :: {:ok, config_value()} | {:error, Error.t()}
  def get_config_value(config, path) when is_list(path) do
    # First validate path security
    if not validate_path_security(path) do
      {:error,
       Error.new(
         code: 1000,
         error_type: :security_violation,
         message: "Configuration path contains potentially malicious components: #{inspect(path)}",
         context: %{path: path, reason: :malicious_path},
         category: :config,
         subcategory: :security,
         severity: :high
       )}
    else
      try do
        # We need to check if the path exists, not just if the value is nil
        case get_nested_value(config, path) do
          {:ok, value} ->
            {:ok, value}

          {:error, :path_not_found} ->
            {:error,
             Error.new(
               error_type: :config_path_not_found,
               message: "Configuration path not found: #{inspect(path)}",
               context: %{path: path},
               category: :config,
               subcategory: :access,
               severity: :medium
             )}
        end
      rescue
        error ->
          Logger.warning(
            "Failed to get config value for path #{inspect(path)}: #{Exception.message(error)}"
          )

          {:error,
           Error.new(
             error_type: :config_path_invalid,
             message: "Invalid configuration path: #{Exception.message(error)}",
             context: %{path: path, error: Exception.message(error)},
             category: :config,
             subcategory: :access,
             severity: :medium
           )}
      end
    end
  end

  def get_config_value(_config, path) do
    Logger.warning("Invalid path provided to get_config_value: #{inspect(path)}")

    {:error,
     Error.new(
       error_type: :invalid_path,
       message: "Invalid path type: #{inspect(path)}",
       context: %{path: path},
       category: :config,
       subcategory: :validation,
       severity: :medium
     )}
  end

  # Helper function to traverse the path and distinguish between nil values and non-existent paths
  defp get_nested_value(data, []) do
    {:ok, data}
  end

  defp get_nested_value(data, [key | rest]) when is_map(data) do
    if Map.has_key?(data, key) do
      get_nested_value(Map.get(data, key), rest)
    else
      {:error, :path_not_found}
    end
  end

  defp get_nested_value(_data, _path) do
    # We hit a non-map value before exhausting the path
    {:error, :path_not_found}
  end

  @doc """
  Merge configuration with environment overrides.
  """
  @spec merge_env_config(Config.t(), keyword()) :: Config.t()
  def merge_env_config(%Config{} = config, env_config) when is_list(env_config) do
    Enum.reduce(env_config, config, fn {key, value}, acc ->
      if Map.has_key?(acc, key) do
        current_value = Map.get(acc, key)
        merged_value = deep_merge(current_value, value)
        Map.put(acc, key, merged_value)
      else
        acc
      end
    end)
  end

  @doc """
  Merge configuration with keyword list overrides.
  """
  @spec merge_opts_config(Config.t(), keyword()) :: Config.t()
  def merge_opts_config(%Config{} = config, opts) when is_list(opts) do
    Enum.reduce(opts, config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Build a configuration from environment and options.
  """
  @spec build_config(keyword()) :: {:ok, Config.t()} | {:error, Error.t()}
  def build_config(opts \\ []) do
    base_config = Config.new()
    env_config = Application.get_all_env(:foundation)

    merged_config =
      base_config
      |> merge_env_config(env_config)
      |> merge_opts_config(opts)

    case ConfigValidator.validate(merged_config) do
      :ok -> {:ok, merged_config}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reset configuration to defaults.
  """
  @spec reset_config() :: Config.t()
  def reset_config do
    Config.new()
  end

  @doc """
  Create a configuration diff between two configs.
  """
  @spec diff_configs(Config.t(), Config.t()) :: map()
  def diff_configs(%Config{} = old_config, %Config{} = new_config) do
    old_map = Map.from_struct(old_config)
    new_map = Map.from_struct(new_config)

    create_diff(old_map, new_map, [])
  end

  ## Private Functions

  defp deep_merge(left, right) when is_map(left) and is_list(right) do
    right_map = Enum.into(right, %{})

    Map.merge(left, right_map, fn _key, left_val, right_val ->
      deep_merge(left_val, right_val)
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      deep_merge(left_val, right_val)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp create_diff(old_map, new_map, path) when is_map(old_map) and is_map(new_map) do
    all_keys = MapSet.union(MapSet.new(Map.keys(old_map)), MapSet.new(Map.keys(new_map)))

    Enum.reduce(all_keys, %{}, fn key, acc ->
      old_val = Map.get(old_map, key)
      new_val = Map.get(new_map, key)
      current_path = path ++ [key]

      cond do
        old_val == new_val ->
          acc

        is_map(old_val) and is_map(new_val) ->
          nested_diff = create_diff(old_val, new_val, current_path)
          if map_size(nested_diff) > 0, do: Map.put(acc, key, nested_diff), else: acc

        true ->
          Map.put(acc, key, %{old: old_val, new: new_val, path: current_path})
      end
    end)
  end

  defp create_diff(old_val, new_val, path) do
    if old_val == new_val do
      %{}
    else
      %{old: old_val, new: new_val, path: path}
    end
  end

  defp create_error(error_type, message, context) do
    error =
      Error.new(
        error_type: error_type,
        message: message,
        context: context,
        category: :config,
        subcategory: :runtime,
        severity: :medium
      )

    {:error, error}
  end

  # Security validation functions

  # Validate that a configuration path is secure and doesn't contain malicious components.
  defp validate_path_security(path) when is_list(path) do
    # Check path length (prevent DoS via deep nesting)
    if length(path) > 50 do
      false
    else
      # Check each component of the path
      Enum.all?(path, &validate_path_component/1)
    end
  end

  defp validate_path_component(component) when is_atom(component) do
    component_str = Atom.to_string(component)

    # Reject dangerous atom names
    dangerous_patterns = [
      "Elixir.System",
      "Elixir.File",
      "Elixir.Code",
      "Elixir.Process",
      "Elixir.Node",
      "Elixir.Kernel",
      "__struct__",
      "__info__"
    ]

    not Enum.any?(dangerous_patterns, fn pattern ->
      String.contains?(component_str, pattern)
    end)
  end

  defp validate_path_component(component) when is_binary(component) do
    # Allow reasonable string components, reject obvious injection attempts
    dangerous_patterns = [
      "../",
      "etc/passwd",
      "DROP TABLE",
      "<script>",
      "eval_string"
    ]

    not Enum.any?(dangerous_patterns, fn pattern ->
      String.contains?(String.downcase(component), String.downcase(pattern))
    end)
  end

  defp validate_path_component(_other) do
    # Reject non-atom, non-string components
    false
  end

  # Validate that a configuration value is secure and doesn't contain dangerous content.
  defp validate_value_security(value) do
    cond do
      is_function(value) ->
        # Reject function values (potential code execution)
        false

      is_binary(value) and byte_size(value) > 1_000_000 ->
        # Reject extremely large strings (>1MB)
        false

      is_map(value) and Map.has_key?(value, :__struct__) ->
        # Reject structs referencing system modules
        struct_module = Map.get(value, :__struct__)

        case struct_module do
          System -> false
          File -> false
          Code -> false
          Process -> false
          _ -> validate_nested_value_security(value)
        end

      is_map(value) or is_list(value) ->
        # Recursively validate nested structures
        validate_nested_value_security(value)

      true ->
        # Allow primitive types
        true
    end
  end

  defp validate_nested_value_security(value, depth \\ 0) do
    # Prevent deep nesting DoS
    if depth > 20 do
      false
    else
      cond do
        is_map(value) ->
          Enum.all?(value, fn {k, v} ->
            validate_value_security(k) and validate_nested_value_security(v, depth + 1)
          end)

        is_list(value) ->
          Enum.all?(value, fn v ->
            validate_nested_value_security(v, depth + 1)
          end)

        true ->
          validate_value_security(value)
      end
    end
  end

  defp get_value_type(value) do
    cond do
      is_function(value) -> :function
      is_map(value) and Map.has_key?(value, :__struct__) -> :struct
      is_map(value) -> :map
      is_list(value) -> :list
      is_binary(value) -> :binary
      is_atom(value) -> :atom
      is_number(value) -> :number
      true -> :unknown
    end
  end
end
