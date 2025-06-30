import Config

# Development environment configuration
config :foundation,
  dev: [
    debug_mode: true,
    verbose_logging: true,
    performance_monitoring: true
  ]

# Enable debug logging in development
config :logger,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  # metadata: [:request_id],
  compile_time_purge_matching: []

# For even better error formatting
config :logger, :console,
  format: "\n$time [$level] $metadata\n$message\n",
  metadata: [
    :module,
    :function,
    :line,
    # Common metadata keys used throughout the application
    :agent_id,
    :error,
    :pid,
    :reason,
    :sensor_id,
    :service,
    :signal_id,
    :task_id
  ]



# import Config

# # Development configuration
# config :foundation,
#   # More verbose logging in development
#   log_level: :debug,

#   # Enhanced AI configuration for development
#   ai: [
#     planning: [
#       default_strategy: :full_trace,  # Full tracing in dev
#       performance_target: 0.1,       # Accept 10% overhead in dev
#       sampling_rate: 1.0              # Total recall in dev
#     ]
#   ],

#   # Larger capture buffers for development
#   capture: [
#     ring_buffer: [
#       size: 2_097_152,              # 2MB buffer in dev
#       max_events: 200_000
#     ],
#     processing: [
#       batch_size: 500,              # Smaller batches for responsiveness
#       flush_interval: 50            # More frequent flushing
#     ]
#   ],

#   # Enhanced storage for development
#   storage: [
#     hot: [
#       max_events: 2_000_000,        # 2M events in dev
#       max_age_seconds: 7200,        # 2 hours in dev
#       prune_interval: 30_000        # Prune every 30 seconds
#     ]
#   ],

#   # Enable development interface features
#   interface: [
#     iex_helpers: true,
#     query_timeout: 10_000,          # Longer timeout for dev queries
#     web: [
#       enable: false,                # Keep disabled for now
#       port: 4001                    # Different port to avoid conflicts
#     ]
#   ]

# config :foundation, :pattern_matcher,
#   # More verbose logging in development
#   log_level: :debug,
#   enable_performance_metrics: true,

#   # Relaxed timeouts for development
#   pattern_match_timeout: 1000,
#   function_analysis_timeout: 50
