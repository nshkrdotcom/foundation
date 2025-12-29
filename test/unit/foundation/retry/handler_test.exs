defmodule Foundation.Retry.HandlerTest do
  use ExUnit.Case, async: true

  alias Foundation.Retry.Handler

  defmodule NonRetryableError do
    defstruct []

    def retryable?(_error), do: false
  end

  test "retry?/2 respects max_retries" do
    handler = %Handler{
      max_retries: 1,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: 1_000,
      attempt: 1,
      last_progress_at: System.monotonic_time(:millisecond),
      start_time: System.monotonic_time(:millisecond)
    }

    refute Handler.retry?(handler, :error)
  end

  test "retry?/2 honors retryable?/1 when exported by the error struct" do
    handler = Handler.new(max_retries: 5)
    refute Handler.retry?(handler, %NonRetryableError{})
  end

  test "next_delay/1 uses exponential backoff when jitter is disabled" do
    handler =
      Handler.new(
        base_delay_ms: 100,
        max_delay_ms: 1_000,
        jitter_pct: 0.0
      )

    assert Handler.next_delay(%{handler | attempt: 0}) == 100
    assert Handler.next_delay(%{handler | attempt: 3}) == 800
    assert Handler.next_delay(%{handler | attempt: 4}) == 1_000
  end

  test "next_delay/1 applies symmetric jitter within bounds" do
    handler =
      Handler.new(
        base_delay_ms: 100,
        max_delay_ms: 1_000,
        jitter_pct: 0.25
      )

    delay = Handler.next_delay(%{handler | attempt: 0})
    assert delay >= 75
    assert delay <= 125
  end

  test "progress_timeout?/1 respects attempt and last progress" do
    now = System.monotonic_time(:millisecond)

    handler = %Handler{
      max_retries: 5,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: 50,
      attempt: 0,
      last_progress_at: now - 100,
      start_time: now
    }

    refute Handler.progress_timeout?(handler)

    handler = %{handler | attempt: 1}
    assert Handler.progress_timeout?(handler)
  end

  test "progress_timeout?/1 ignores nil timeout" do
    now = System.monotonic_time(:millisecond)

    handler = %Handler{
      max_retries: 5,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: nil,
      attempt: 1,
      last_progress_at: now - 100,
      start_time: now
    }

    refute Handler.progress_timeout?(handler)
  end

  test "progress_timeout?/1 ignores :infinity timeout" do
    now = System.monotonic_time(:millisecond)

    handler = %Handler{
      max_retries: 5,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: :infinity,
      attempt: 1,
      last_progress_at: now - 100,
      start_time: now
    }

    refute Handler.progress_timeout?(handler)
  end

  test "record_progress/1 updates last_progress_at" do
    handler = Handler.new()
    updated = Handler.record_progress(handler)
    assert updated.last_progress_at >= handler.last_progress_at
  end

  test "elapsed_ms/1 returns elapsed time since start" do
    now = System.monotonic_time(:millisecond)

    handler = %Handler{
      max_retries: 5,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: 50,
      attempt: 0,
      last_progress_at: now,
      start_time: now - 25
    }

    assert Handler.elapsed_ms(handler) >= 25
  end
end
