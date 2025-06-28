import Config

# Foundation Layer Configuration
config :foundation,
  # AI Provider Configuration
  ai: [
    provider: :mock,
    api_key: nil,
    model: "gpt-4",
    analysis: [
      max_file_size: 1_000_000,
      timeout: 30_000,
      cache_ttl: 3600
    ],
    planning: [
      default_strategy: :balanced,
      performance_target: 0.01,
      sampling_rate: 1.0
    ]
  ],

  # Capture Configuration
  capture: [
    ring_buffer: [
      size: 1024,
      max_events: 1000,
      overflow_strategy: :drop_oldest,
      num_buffers: :schedulers
    ],
    processing: [
      batch_size: 100,
      flush_interval: 50,
      max_queue_size: 1000
    ],
    vm_tracing: [
      enable_spawn_trace: true,
      enable_exit_trace: true,
      enable_message_trace: false,
      trace_children: true
    ]
  ],

  # Storage Configuration
  storage: [
    hot: [
      max_events: 100_000,
      max_age_seconds: 3600,
      prune_interval: 60_000
    ],
    warm: [
      enable: false,
      path: "./foundation_data",
      max_size_mb: 100,
      compression: :zstd
    ],
    cold: [
      enable: false
    ]
  ],

  # Interface Configuration
  interface: [
    query_timeout: 10_000,
    max_results: 1000,
    enable_streaming: true
  ],

  # Development Configuration
  dev: [
    debug_mode: false,
    verbose_logging: false,
    performance_monitoring: true
  ],

  # MABEAM Configuration (extracted but still part of Foundation config)
  mabeam: [
    # Feature flag for gradual migration to unified registry
    use_unified_registry: true,

    # Legacy registry configuration (when use_unified_registry is false)
    legacy_registry: [
      backend: MABEAM.ProcessRegistry.Backend.LocalETS,
      auto_start: false
    ],

    # Migration settings
    migration: [
      auto_migrate_on_start: false,
      cleanup_legacy_on_migration: true,
      validate_after_migration: true
    ]
  ]




# Import environment specific config
import_config "#{config_env()}.exs"




# import Config

# # Foundation Configuration
# config :foundation,
#   # AI Configuration
#   ai: [
#     # AI provider configuration (future LLM integration)
#     provider: :mock,
#     api_key: nil,
#     model: "gpt-4",

#     # Code analysis settings
#     analysis: [
#       max_file_size: 1_000_000,  # 1MB max file size for analysis
#       timeout: 30_000,           # 30 second timeout for analysis
#       cache_ttl: 3600           # 1 hour cache TTL for analysis results
#     ],

#     # Instrumentation planning
#     planning: [
#       default_strategy: :balanced,  # :minimal, :balanced, :full_trace
#       performance_target: 0.01,     # 1% max overhead target
#       sampling_rate: 1.0            # 100% sampling by default (total recall)
#     ]
#   ],

#   # Event Capture Configuration
#   capture: [
#     # Ring buffer settings
#     ring_buffer: [
#       size: 1_048_576,           # 1MB buffer size
#       max_events: 100_000,       # Max events before overflow
#       overflow_strategy: :drop_oldest,
#       num_buffers: :schedulers   # One buffer per scheduler by default
#     ],

#     # Event processing
#     processing: [
#       batch_size: 1000,          # Events per batch
#       flush_interval: 100,       # Flush every 100ms
#       max_queue_size: 10_000     # Max queued events before backpressure
#     ],

#     # VM tracing configuration
#     vm_tracing: [
#       enable_spawn_trace: true,
#       enable_exit_trace: true,
#       enable_message_trace: false,  # Can be very noisy
#       trace_children: true
#     ]
#   ],

#   # Storage Configuration
#   storage: [
#     # Hot storage (ETS) - recent events
#     hot: [
#       max_events: 1_000_000,     # 1M events in hot storage
#       max_age_seconds: 3600,     # 1 hour max age
#       prune_interval: 60_000     # Prune every minute
#     ],

#     # Warm storage (disk) - archived events
#     warm: [
#       enable: false,             # Disable warm storage initially
#       path: "./foundation_data",
#       max_size_mb: 1000,         # 1GB max warm storage
#       compression: :zstd
#     ],

#     # Cold storage (future) - long-term archival
#     cold: [
#       enable: false
#     ]
#   ],

#   # Developer Interface
#   interface: [
#     # IEx helpers
#     iex_helpers: true,

#     # Query timeouts
#     query_timeout: 5000,         # 5 second default query timeout

#     # Web interface (future)
#     web: [
#       enable: false,
#       port: 4000
#     ]
#   ],

#   # Instrumentation Configuration
#   instrumentation: [
#     # Default instrumentation levels
#     default_level: :function_boundaries,  # :none, :function_boundaries, :full_trace

#     # Module-specific overrides
#     module_overrides: %{
#       # Example: MyApp.ImportantModule => :full_trace
#     },

#     # Function-specific overrides
#     function_overrides: %{
#       # Example: {MyApp.FastModule, :critical_function, 2} => :minimal
#     },

#     # Automatic exclusions
#     exclude_modules: [
#       Foundation,               # Don't instrument ourselves
#       :logger,
#       :gen_server,
#       :supervisor
#     ]
#   ]


# config :foundation, :pattern_matcher,
#   # Performance settings
#   pattern_match_timeout: 500,
#   function_analysis_timeout: 10,
#   max_memory_usage_mb: 100,

#   # Default confidence thresholds
#   default_confidence_threshold: 0.7,
#   high_confidence_threshold: 0.9,

#   # Cache settings
#   enable_pattern_cache: true,
#   cache_ttl_minutes: 30,

#   # Pattern library settings
#   load_default_patterns: true,
#   custom_pattern_paths: [],

#   # Analysis settings
#   enable_ast_analysis: true,
#   enable_behavioral_analysis: true,
#   enable_anti_pattern_analysis: true,
#   context_sensitive_matching: false

# # Environment-specific configuration
# import_config "#{config_env()}.exs"
