import Config

# Production configuration
config :logger, level: :info

config :foundation,
  storage_backend: :persistent,
  telemetry_enabled: true
