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

    test "uses retry-after HTTP-date when present" do
      future =
        DateTime.utc_now()
        |> DateTime.add(10, :second)
        |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

      headers = [{"Retry-After", future}]
      delay = HTTP.parse_retry_after(headers)

      assert delay > 1_000
      assert delay <= 10_000
    end

    test "uses retry-after obsolete RFC 850 HTTP-date when present" do
      future =
        DateTime.utc_now()
        |> DateTime.add(10, :second)
        |> Calendar.strftime("%A, %d-%b-%y %H:%M:%S GMT")

      headers = [{"Retry-After", future}]
      delay = HTTP.parse_retry_after(headers)

      assert delay > 1_000
      assert delay <= 10_000
    end

    test "uses retry-after asctime HTTP-date when present" do
      future =
        DateTime.utc_now()
        |> DateTime.add(10, :second)

      future =
        Calendar.strftime(future, "%a %b") <>
          " " <>
          String.pad_leading(Integer.to_string(future.day), 2, " ") <>
          Calendar.strftime(future, " %H:%M:%S %Y")

      headers = [{"Retry-After", future}]
      delay = HTTP.parse_retry_after(headers)

      assert delay > 1_000
      assert delay <= 10_000
    end

    test "defaults when header is missing or invalid" do
      headers = [{"retry-after", "not-a-number"}]
      assert HTTP.parse_retry_after(headers) == 1_000
      assert HTTP.parse_retry_after([]) == 1_000
    end
  end

  describe "retryable_status_for_method?/3" do
    test "matches caller-provided status rules by method" do
      rules = [all: [429], get: [500, 503], delete: [500, 503]]

      assert HTTP.retryable_status_for_method?(429, :patch, rules)
      assert HTTP.retryable_status_for_method?(500, :get, rules)
      assert HTTP.retryable_status_for_method?(503, "DELETE", rules)

      refute HTTP.retryable_status_for_method?(500, :post, rules)
      refute HTTP.retryable_status_for_method?(408, :get, rules)
    end
  end

  describe "should_retry_for_method?/3" do
    test "honors x-should-retry overrides before method-aware rules" do
      rules = [all: [429], get: [500, 503], delete: [500, 503]]

      response = %{status: 500, headers: [{"x-should-retry", "false"}]}
      refute HTTP.should_retry_for_method?(:get, response, rules)

      response = %{status: 200, headers: [{"x-should-retry", "true"}]}
      assert HTTP.should_retry_for_method?(:post, response, rules)
    end

    test "uses method-aware rules when no override is present" do
      rules = [all: [429], get: [500, 503], delete: [500, 503]]

      assert HTTP.should_retry_for_method?(:delete, %{status: 503, headers: []}, rules)
      assert HTTP.should_retry_for_method?(:post, %{status: 429, headers: []}, rules)

      refute HTTP.should_retry_for_method?(:post, %{status: 500, headers: []}, rules)
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

      response = %{status: 500, headers: []}
      assert HTTP.should_retry?(response)

      response = %{status: 200, headers: []}
      refute HTTP.should_retry?(response)
    end
  end
end
