import Config

# Test environment configuration
config :foundation,
  environment: :test,   # Enable test environment checks
  test_mode: true,      # Enable test mode for test supervisor
  debug_registry: false,
  ecto_repos: [],
  registry_impl: MABEAM.AgentRegistry,  # Fix registry configuration
  ai: [
    provider: :mock,
    analysis: [
      max_file_size: 100_000,  # Smaller for tests
      timeout: 5_000,          # Faster timeouts
      cache_ttl: 60
    ],
    planning: [
      default_strategy: :fast,
      performance_target: 0.1,
      sampling_rate: 1.0
    ]
  ],

  capture: [
    processing: [
      batch_size: 10,      # Smaller batches for tests
      flush_interval: 10,
      max_queue_size: 100
    ]
  ],

  dev: [
    debug_mode: false,     # Reduce noise in tests
    verbose_logging: false,
    performance_monitoring: false
  ]

# Configure test logging - allow info for tests that check logs
config :logger,
  level: :info,  # Allow info logs for capture_log tests
  backends: [:console]

config :logger, :console,
  format: "[$level] $message\n",
  metadata: []

# Configure ExUnit for comprehensive testing
config :foundation, ExUnit,
  timeout: 30_000,
  exclude: [
    :slow,
    :integration,
    :end_to_end,
    :ai,
    :capture,
    :phoenix,
    :distributed,
    :real_world,
    :benchmark,
    :stress,
    :memory,
    :scalability,
    :regression,
    :scenario
  ]

# Add temporary test configuration for better debugging
config :foundation, :foundation,
  debug_config: true,
  debug_events: true

# import Config

# # Configure Logger to only show errors during tests (reduce noise)
# config :logger, level: :error

# # Test configuration
# config :foundation,
#   # Minimal logging in tests
#   log_level: :error,

#   # Test-friendly AI configuration
#   ai: [
#     provider: :mock,                # Always use mock in tests
#     planning: [
#       default_strategy: :minimal,   # Minimal instrumentation in tests
#       performance_target: 0.5,     # Accept higher overhead in tests
#       sampling_rate: 1.0            # Full sampling for predictable tests
#     ]
#   ],

#   # Force mock provider in tests (overrides auto-detection)
#   llm_provider: "mock",

#   # Smaller buffers for faster tests
#   capture: [
#     ring_buffer: [
#       size: 65_536,                 # 64KB buffer for tests
#       max_events: 1000
#     ],
#     processing: [
#       batch_size: 10,               # Small batches for quick processing
#       flush_interval: 1             # Immediate flushing in tests
#     ]
#   ],

#   # Minimal storage for tests
#   storage: [
#     hot: [
#       max_events: 10_000,           # 10K events max in tests
#       max_age_seconds: 60,          # 1 minute max age
#       prune_interval: 1000          # Prune every second
#     ]
#   ],

#   # Test interface configuration
#   interface: [
#     iex_helpers: false,             # Disable IEx helpers in tests
#     query_timeout: 1000             # Quick timeout for tests
#   ],

#   state_manager: Foundation.ASTRepository.Enhanced.CFGGenerator.StateManager,
#   ast_utilities: Foundation.ASTRepository.Enhanced.CFGGenerator.ASTUtilities,
#   ast_processor: Foundation.ASTRepository.Enhanced.CFGGenerator.ASTProcessor









# config :foundation, :pattern_matcher,
#   # Faster execution for tests
#   pattern_match_timeout: 100,
#   function_analysis_timeout: 5,

#   # Disable caching for predictable tests
#   enable_pattern_cache: false,

#   # Test-specific settings
#   log_level: :warning

# # Exclude live API tests by default
# # To run live tests: mix test --only live_api
# # To include all tests: mix test --include live_api
# ExUnit.configure(
#   exclude: [:live_api],
#   formatters: [ExUnit.CLIFormatter],
#   colors: [
#     enabled: true,
#     success: :green,
#     invalid: :yellow,
#     failure: :red,
#     error: :red,
#     extra_info: :cyan,
#     diff_delete: :red,
#     diff_insert: :green
#   ],
#   trace: true,  # Show each test as it runs
#   max_cases: 1, # Force trace mode (shows individual tests)
#   timeout: 60_000,
#   max_failures: :infinity
# )
