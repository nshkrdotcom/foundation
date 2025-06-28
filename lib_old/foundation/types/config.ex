defmodule Foundation.Types.Config do
  @moduledoc """
  Pure data structure for Foundation configuration.

  Contains no business logic - just data and Access implementation.
  All validation and manipulation logic is in separate modules.

  This struct defines the complete configuration schema for Foundation,
  including AI, capture, storage, interface, and development settings.

  See `@type t` for the complete type specification.

  ## Examples

      iex> config = Foundation.Types.Config.new()
      iex> config.ai.provider
      :mock

      iex> config = Foundation.Types.Config.new(dev: %{debug_mode: true})
      iex> config.dev.debug_mode
      true
  """

  @behaviour Access

  # All fields have meaningful defaults, so no @enforce_keys needed
  defstruct [
    # AI Configuration
    ai: %{
      provider: :mock,
      api_key: nil,
      model: "gpt-4",
      analysis: %{
        max_file_size: 1_000_000,
        timeout: 30_000,
        cache_ttl: 3600
      },
      planning: %{
        default_strategy: :balanced,
        performance_target: 0.01,
        sampling_rate: 1.0
      }
    },

    # Capture Configuration
    capture: %{
      ring_buffer: %{
        size: 1024,
        max_events: 1000,
        overflow_strategy: :drop_oldest,
        num_buffers: :schedulers
      },
      processing: %{
        batch_size: 100,
        flush_interval: 50,
        max_queue_size: 1000
      },
      vm_tracing: %{
        enable_spawn_trace: true,
        enable_exit_trace: true,
        enable_message_trace: false,
        trace_children: true
      }
    },

    # Storage Configuration
    storage: %{
      hot: %{
        max_events: 100_000,
        max_age_seconds: 3600,
        prune_interval: 60_000
      },
      warm: %{
        enable: false,
        path: "./foundation_data",
        max_size_mb: 100,
        compression: :zstd
      },
      cold: %{
        enable: false
      }
    },

    # Interface Configuration
    interface: %{
      query_timeout: 10_000,
      max_results: 1000,
      enable_streaming: true
    },

    # Development Configuration
    dev: %{
      debug_mode: false,
      verbose_logging: false,
      performance_monitoring: true
    },

    # Infrastructure Configuration
    infrastructure: %{
      rate_limiting: %{
        default_rules: %{
          # 100 requests per minute
          api_calls: %{scale: 60_000, limit: 100},
          # 500 queries per minute
          db_queries: %{scale: 60_000, limit: 500},
          # 10 operations per second
          file_operations: %{scale: 1_000, limit: 10}
        },
        enabled: true,
        # 5 minutes
        cleanup_interval: 300_000
      },
      circuit_breaker: %{
        default_config: %{
          failure_threshold: 5,
          recovery_time: 30_000,
          call_timeout: 5_000
        },
        enabled: true
      },
      connection_pool: %{
        default_config: %{
          size: 10,
          max_overflow: 5,
          strategy: :lifo
        },
        enabled: true
      },
      # Dynamic protection configurations - added for unified config
      protection: %{}
    }
  ]

  @typedoc "AI configuration section"
  @type ai_config :: %{
          provider: :mock | :openai | :anthropic,
          api_key: String.t() | nil,
          model: String.t(),
          analysis: %{
            max_file_size: pos_integer(),
            timeout: pos_integer(),
            cache_ttl: pos_integer()
          },
          planning: %{
            default_strategy: :balanced | :fast | :thorough,
            performance_target: float(),
            sampling_rate: float()
          }
        }

  @typedoc "Capture configuration section"
  @type capture_config :: %{
          ring_buffer: %{
            size: pos_integer(),
            max_events: pos_integer(),
            overflow_strategy: :drop_oldest | :drop_newest | :error,
            num_buffers: :schedulers | pos_integer()
          },
          processing: %{
            batch_size: pos_integer(),
            flush_interval: pos_integer(),
            max_queue_size: pos_integer()
          },
          vm_tracing: %{
            enable_spawn_trace: boolean(),
            enable_exit_trace: boolean(),
            enable_message_trace: boolean(),
            trace_children: boolean()
          }
        }

  @typedoc "Storage configuration section"
  @type storage_config :: %{
          hot: %{
            max_events: pos_integer(),
            max_age_seconds: pos_integer(),
            prune_interval: pos_integer()
          },
          warm: %{
            enable: boolean(),
            path: String.t(),
            max_size_mb: pos_integer(),
            compression: :zstd | :gzip | :none
          },
          cold: %{
            enable: boolean()
          }
        }

  @typedoc "Interface configuration section"
  @type interface_config :: %{
          query_timeout: pos_integer(),
          max_results: pos_integer(),
          enable_streaming: boolean()
        }

  @typedoc "Development configuration section"
  @type dev_config :: %{
          debug_mode: boolean(),
          verbose_logging: boolean(),
          performance_monitoring: boolean()
        }

  @typedoc "Infrastructure configuration section"
  @type infrastructure_config :: %{
          rate_limiting: %{
            default_rules: %{atom() => %{scale: pos_integer(), limit: pos_integer()}},
            enabled: boolean(),
            cleanup_interval: pos_integer()
          },
          circuit_breaker: %{
            default_config: %{
              failure_threshold: pos_integer(),
              recovery_time: pos_integer(),
              call_timeout: pos_integer()
            },
            enabled: boolean()
          },
          connection_pool: %{
            default_config: %{
              size: pos_integer(),
              max_overflow: pos_integer(),
              strategy: :lifo | :fifo
            },
            enabled: boolean()
          },
          protection: %{atom() => map()}
        }

  @type t :: %__MODULE__{
          ai: ai_config(),
          capture: capture_config(),
          storage: storage_config(),
          interface: interface_config(),
          dev: dev_config(),
          infrastructure: infrastructure_config()
        }

  ## Access Behavior Implementation

  @doc """
  Fetch a configuration key.

  Implementation of the Access behaviour for configuration structs.
  """
  @impl Access
  @spec fetch(t(), atom()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = config, key) do
    config
    |> Map.from_struct()
    |> Map.fetch(key)
  end

  @doc """
  Get and update a configuration key.

  Implementation of the Access behaviour for configuration structs.
  """
  @impl Access
  @spec get_and_update(t(), atom(), (term() -> {term(), term()} | :pop)) ::
          {term(), t()}
  def get_and_update(%__MODULE__{} = config, key, function) do
    map_config = Map.from_struct(config)

    case Map.get_and_update(map_config, key, function) do
      {current_value, updated_map} ->
        case struct(__MODULE__, updated_map) do
          updated_config when is_struct(updated_config, __MODULE__) ->
            {current_value, updated_config}

          _ ->
            {current_value, config}
        end
    end
  end

  @doc """
  Pop a configuration key.

  Implementation of the Access behaviour for configuration structs.
  """
  @impl Access
  @spec pop(t(), atom()) :: {term(), t()}
  def pop(%__MODULE__{} = config, key) do
    map_config = Map.from_struct(config)
    {value, updated_map} = Map.pop(map_config, key)
    updated_config = struct(__MODULE__, updated_map)
    {value, updated_config}
  end

  @doc """
  Create a new configuration with default values.

  ## Examples

      iex> config = Foundation.Types.Config.new()
      iex> config.ai.provider
      :mock

      iex> config.capture.ring_buffer.size
      1024
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Create a new configuration with overrides.

  Performs deep merging of nested configuration maps.

  ## Parameters
  - `overrides`: Keyword list of configuration overrides

  ## Examples

      iex> config = Foundation.Types.Config.new(dev: %{debug_mode: true})
      iex> config.dev.debug_mode
      true

      iex> config = Foundation.Types.Config.new(ai: %{provider: :openai})
      iex> config.ai.provider
      :openai
  """
  @spec new(keyword()) :: t()
  def new(overrides) do
    config = new()

    Enum.reduce(overrides, config, fn {key, value}, acc ->
      case Map.get(acc, key) do
        existing_value when is_map(existing_value) and is_map(value) ->
          # Deep merge maps
          merged_value = deep_merge(existing_value, value)
          Map.put(acc, key, merged_value)

        _ ->
          # Replace non-map values
          Map.put(acc, key, value)
      end
    end)
  end

  # Helper function for deep merging maps
  @spec deep_merge(map(), map()) :: map()
  defp deep_merge(original, override) when is_map(original) and is_map(override) do
    Map.merge(original, override, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
