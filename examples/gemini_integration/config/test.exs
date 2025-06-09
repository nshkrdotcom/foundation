import Config

# Test configuration
config :logger, level: :warn

config :foundation,
  storage_backend: :memory,
  telemetry_enabled: false
