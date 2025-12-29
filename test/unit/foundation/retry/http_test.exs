defmodule Foundation.Retry.HTTPTest do
  use ExUnit.Case, async: true

  alias Foundation.Retry.HTTP

  describe "retry_delay/1" do
    test "returns jittered delays within the Python parity range" do
      delay = HTTP.retry_delay(0)
      assert delay >= 375
      assert delay <= 500

      delay = HTTP.retry_delay(5)
      assert delay >= 7_500
      assert delay <= 10_000
    end
  end

  describe "retry_delay/3" do
    test "respects custom initial and max delay bounds" do
      delay = HTTP.retry_delay(0, 1_000, 2_000)
      assert delay >= 750
      assert delay <= 1_000

      delay = HTTP.retry_delay(2, 1_000, 2_000)
      assert delay >= 1_500
      assert delay <= 2_000
    end
  end

  describe "retryable_status?/1" do
    test "matches the Python SDK retry status list" do
      assert HTTP.retryable_status?(408)
      assert HTTP.retryable_status?(409)
      assert HTTP.retryable_status?(429)
      assert HTTP.retryable_status?(500)
      assert HTTP.retryable_status?(599)
      refute HTTP.retryable_status?(200)
      refute HTTP.retryable_status?(404)
    end
  end

  describe "parse_retry_after/1" do
    test "uses retry-after-ms when present" do
      headers = [{"retry-after-ms", "2500"}]
      assert HTTP.parse_retry_after(headers) == 2_500
    end

    test "uses retry-after seconds when present" do
      headers = [{"Retry-After", "2"}]
      assert HTTP.parse_retry_after(headers) == 2_000
    end

    test "defaults when header is missing or invalid" do
      headers = [{"retry-after", "not-a-number"}]
      assert HTTP.parse_retry_after(headers) == 1_000
      assert HTTP.parse_retry_after([]) == 1_000
    end
  end

  describe "should_retry?/1" do
    test "honors x-should-retry overrides" do
      response = %{status: 500, headers: [{"x-should-retry", "false"}]}
      refute HTTP.should_retry?(response)

      response = %{status: 200, headers: [{"x-should-retry", "true"}]}
      assert HTTP.should_retry?(response)
    end

    test "falls back to retryable status codes" do
      response = %{status: 429, headers: []}
      assert HTTP.should_retry?(response)

      response = %{status: 200, headers: []}
      refute HTTP.should_retry?(response)
    end
  end
end
