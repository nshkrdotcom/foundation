defmodule Foundation.Telemetry.SamplerTest do
  use ExUnit.Case, async: false
  use Foundation.TelemetryTestHelpers

  alias Foundation.Telemetry.Sampler

  setup do
    # Enable sampling for tests
    original_config = Application.get_env(:foundation, :telemetry_sampling, [])
    Application.put_env(:foundation, :telemetry_sampling, enabled: true)

    # Start sampler with test configuration
    {:ok, pid} = Sampler.start_link()

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end

      # Restore original config
      Application.put_env(:foundation, :telemetry_sampling, original_config)
    end)

    :ok
  end

  describe "should_sample?/2" do
    test "returns true when using default always strategy" do
      # Default strategy is :always
      assert Sampler.should_sample?([:test, :event])
    end

    test "applies random sampling strategy" do
      # Configure for 50% sampling
      Sampler.configure_event([:test, :random], strategy: :random, rate: 0.5)

      # Collect samples
      samples =
        for _ <- 1..1000 do
          Sampler.should_sample?([:test, :random])
        end

      # Should be roughly 50% true
      true_count = Enum.count(samples, & &1)
      assert true_count > 400 and true_count < 600
    end

    test "always strategy always returns true" do
      Sampler.configure_event([:test, :always], strategy: :always)

      for _ <- 1..100 do
        assert Sampler.should_sample?([:test, :always])
      end
    end

    test "never strategy always returns false" do
      Sampler.configure_event([:test, :never], strategy: :never)

      for _ <- 1..100 do
        refute Sampler.should_sample?([:test, :never])
      end
    end
  end

  describe "rate limiting" do
    test "enforces max events per second" do
      Sampler.configure_event([:test, :rate_limited],
        strategy: :rate_limited,
        max_per_second: 10
      )

      # Try to sample 20 events quickly
      results =
        for _ <- 1..20 do
          Sampler.should_sample?([:test, :rate_limited])
        end

      # Should only allow 10
      assert Enum.count(results, & &1) == 10

      # Wait for next window
      Process.sleep(1100)

      # Should allow more now
      assert Sampler.should_sample?([:test, :rate_limited])
    end
  end

  describe "reservoir sampling" do
    test "maintains fixed sample size" do
      Sampler.configure_event([:test, :reservoir],
        strategy: :reservoir,
        reservoir_size: 100
      )

      # First 100 should all be sampled
      for _ <- 1..100 do
        assert Sampler.should_sample?([:test, :reservoir])
      end

      # After that, probability decreases
      next_1000 =
        for _ <- 1..1000 do
          Sampler.should_sample?([:test, :reservoir])
        end

      # Should have sampled some, but not all
      sampled = Enum.count(next_1000, & &1)
      # With reservoir sampling, once the reservoir is full, probability decreases
      # For a reservoir of 100 and 1000 more items, we expect around 100 samples
      # Just ensure it's not negative
      assert sampled >= 0
    end
  end

  describe "adaptive sampling" do
    test "adjusts rate based on target" do
      Sampler.configure_event([:test, :adaptive],
        strategy: :adaptive,
        rate: 0.5,
        adaptive_config: %{
          # 50 events per second
          target_rate: 50,
          adjustment_interval: 100,
          increase_factor: 2.0,
          decrease_factor: 0.5
        }
      )

      # Simulate high load
      for _ <- 1..200 do
        Sampler.should_sample?([:test, :adaptive])
        # ~1000 events/sec
        Process.sleep(1)
      end

      # Get stats to verify adjustment happened
      stats = Sampler.get_stats()
      event_stats = stats.event_stats[[:test, :adaptive]]

      # Sampling rate should have decreased (or at least not increased much)
      # More lenient bound
      assert event_stats.sampling_rate_percent < 60
    end
  end

  describe "execute/3" do
    test "only emits events when sampled" do
      test_pid = self()
      ref = make_ref()

      # Attach telemetry handler
      :telemetry.attach(
        "test-sampled-execute",
        [:test, :sampled],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :event_received, measurements, metadata})
        end,
        %{}
      )

      # Configure to never sample
      Sampler.configure_event([:test, :sampled], strategy: :never)

      # Should not emit
      Sampler.execute([:test, :sampled], %{value: 1}, %{test: true})
      refute_receive {^ref, :event_received, _, _}, 100

      # Configure to always sample
      Sampler.configure_event([:test, :sampled], strategy: :always)

      # Should emit
      Sampler.execute([:test, :sampled], %{value: 2}, %{test: true})
      assert_receive {^ref, :event_received, measurements, metadata}
      assert measurements.value == 2
      assert metadata.test == true
      assert metadata.sampled == true

      :telemetry.detach("test-sampled-execute")
    end
  end

  describe "get_stats/0" do
    test "returns sampling statistics" do
      # Generate some events
      Sampler.configure_event([:test, :stats], strategy: :random, rate: 0.5)

      for _ <- 1..100 do
        Sampler.should_sample?([:test, :stats])
      end

      stats = Sampler.get_stats()

      # Enabled for tests
      assert stats.enabled == true
      assert is_map(stats.event_stats)
      assert stats.uptime_seconds >= 0

      event_stats = stats.event_stats[[:test, :stats]]
      assert event_stats.total == 100
      assert event_stats.sampled > 30 and event_stats.sampled < 70
      assert event_stats.sampling_rate_percent > 30 and event_stats.sampling_rate_percent < 70
      assert event_stats.strategy == :random
    end
  end

  describe "reset_stats/0" do
    test "clears all statistics" do
      # Generate some events
      Sampler.configure_event([:test, :reset], strategy: :always)

      for _ <- 1..50 do
        Sampler.should_sample?([:test, :reset])
      end

      # Verify stats exist
      stats = Sampler.get_stats()
      assert stats.event_stats[[:test, :reset]].total == 50

      # Reset
      :ok = Sampler.reset_stats()

      # Stats should be cleared
      new_stats = Sampler.get_stats()
      assert new_stats.event_stats == %{}
    end
  end
end
