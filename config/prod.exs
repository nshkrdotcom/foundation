import Config

# Production environment configuration
config :foundation,
  ai: [
    provider: {:system, "FOUNDATION_AI_PROVIDER", :openai},
    api_key: {:system, "FOUNDATION_AI_API_KEY"},
    analysis: [
      max_file_size: 5_000_000,  # Larger files in production
      timeout: 60_000,           # More generous timeouts
      cache_ttl: 7200
    ],
    planning: [
      default_strategy: :balanced,
      performance_target: 0.005,  # Higher performance target
      sampling_rate: 0.1          # Lower sampling rate
    ]
  ],

  capture: [
    processing: [
      batch_size: 1000,
      flush_interval: 100,
      max_queue_size: 10_000
    ]
  ],

  storage: [
    warm: [
      enable: true,
      path: "/var/lib/foundation/data",
      max_size_mb: 1000,
      compression: :zstd
    ],
    cold: [
      enable: true
    ]
  ],

  dev: [
    debug_mode: false,
    verbose_logging: false,
    performance_monitoring: true
  ]

# Production logging configuration
config :logger, level: :info



# import Config

# # Production configuration
# config :foundation,
#   # Minimal logging in production
#   log_level: :info,

#   # Production AI configuration
#   ai: [
#     planning: [
#       default_strategy: :balanced,  # Balanced approach in production
#       performance_target: 0.005,   # 0.5% max overhead in production
#       sampling_rate: 0.1            # 10% sampling to reduce overhead
#     ]
#   ],

#   # Conservative capture settings for production
#   capture: [
#     ring_buffer: [
#       size: 1_048_576,              # 1MB buffer in production
#       max_events: 50_000            # Smaller event limit
#     ],
#     processing: [
#       batch_size: 2000,             # Larger batches for efficiency
#       flush_interval: 500           # Less frequent flushing
#     ]
#   ],

#   # Conservative storage for production
#   storage: [
#     hot: [
#       max_events: 500_000,          # 500K events in production
#       max_age_seconds: 1800,        # 30 minutes in production
#       prune_interval: 300_000       # Prune every 5 minutes
#     ]
#   ],

#   # Production interface configuration
#   interface: [
#     iex_helpers: false,             # Disable IEx helpers in production
#     query_timeout: 3000             # Shorter timeout for production
#   ]
