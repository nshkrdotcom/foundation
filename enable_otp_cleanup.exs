#!/usr/bin/env elixir

# Script to enable OTP cleanup features and test
Mix.install([])

# Start the application components we need
Application.start(:logger)
Application.start(:telemetry)

# Add the project to the code path
Code.append_path("_build/test/lib/foundation/ebin")
Code.append_path("_build/test/lib/jido_system/ebin")

# Start Foundation services
{:ok, _} = Foundation.FeatureFlags.start_link()

IO.puts("🚀 Enabling OTP cleanup features...")

# Enable stage 3 (includes all Process dictionary replacements)
case Foundation.FeatureFlags.enable_otp_cleanup_stage(3) do
  :ok -> 
    IO.puts("✅ Stage 3 enabled successfully!")
    
    # Check status
    flags = [
      :use_ets_agent_registry,
      :use_logger_error_context, 
      :use_genserver_telemetry,
      :use_genserver_span_management,
      :use_ets_sampled_events
    ]
    
    IO.puts("\n📊 Feature Flag Status:")
    for flag <- flags do
      enabled = Foundation.FeatureFlags.enabled?(flag)
      status = if enabled, do: "✅ ENABLED", else: "❌ DISABLED"
      IO.puts("  #{flag}: #{status}")
    end
    
  error -> 
    IO.puts("❌ Failed to enable stage: #{inspect(error)}")
end

IO.puts("\n🧪 Running OTP cleanup tests...")
System.cmd("mix", ["test", "test/foundation/otp_cleanup_integration_test.exs", "--max-failures", "3"], 
  into: IO.stream(:stdio, :line))