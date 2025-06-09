import Config

# Development configuration
config :logger,
  level: :debug,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Make telemetry more verbose in dev
config :foundation,
  storage_backend: :memory,
  telemetry_enabled: true,
  log_level: :debug

# Gemini API configuration
# You can set GEMINI_API_KEY environment variable or put your key here
config :gemini,
  api_key: System.get_env("GEMINI_API_KEY") || "your_api_key_here"
