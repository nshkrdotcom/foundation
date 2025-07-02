defmodule OTPCleanupEnabler do
  @moduledoc """
  Simple script to enable OTP cleanup flags and test
  """
  
  def run do
    # Start mix application
    Mix.start()
    
    # Start the main application
    {:ok, _} = Application.ensure_all_started(:foundation)
    
    IO.puts("🚀 Starting Foundation application...")
    
    # Give services time to start
    Process.sleep(1000)
    
    IO.puts("📊 Enabling OTP cleanup features...")
    
    # Enable individual flags
    flags_to_enable = [
      :use_ets_agent_registry,
      :use_logger_error_context,
      :use_genserver_telemetry,
      :use_genserver_span_management,
      :use_ets_sampled_events
    ]
    
    for flag <- flags_to_enable do
      case Foundation.FeatureFlags.enable(flag) do
        :ok -> IO.puts("✅ Enabled #{flag}")
        error -> IO.puts("❌ Failed to enable #{flag}: #{inspect(error)}")
      end
    end
    
    # Check status
    IO.puts("\n📋 Feature Flag Status:")
    for flag <- flags_to_enable do
      enabled = Foundation.FeatureFlags.enabled?(flag)
      status = if enabled, do: "✅ ENABLED", else: "❌ DISABLED"
      IO.puts("  #{flag}: #{status}")
    end
    
    IO.puts("\n🧪 Running integration test...")
    
    # Run the test to see if Process dictionary usage is eliminated
    System.cmd("mix", ["test", "test/foundation/otp_cleanup_integration_test.exs", "--max-failures", "3"],
      into: IO.stream(:stdio, :line))
  end
end

OTPCleanupEnabler.run()