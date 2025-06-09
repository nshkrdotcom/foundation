import Config

# Configure Foundation
config :foundation,
  # Add any foundation-specific config here
  storage_backend: :memory,
  telemetry_enabled: true

# Configure Gemini (you'll need to set GEMINI_API_KEY environment variable)
config :gemini_ex,
  api_key: System.get_env("GEMINI_API_KEY"),
  model: "gemini-1.5-flash"

# Example of per-environment config
import_config "#{config_env()}.exs"
