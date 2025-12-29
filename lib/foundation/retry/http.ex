defmodule Foundation.Retry.HTTP do
  @moduledoc """
  HTTP retry helpers with Python SDK parity defaults.

  Provides retry delay calculation, status classification, and Retry-After parsing.
  """

  @initial_retry_delay_ms 500
  @max_retry_delay_ms 10_000
  @jitter_min 0.75
  @jitter_max 1.0
  @default_retry_after_ms 1_000

  @type headers :: [{String.t(), String.t()}] | map()

  @doc """
  Calculate the retry delay for the given attempt.
  """
  @spec retry_delay(non_neg_integer()) :: non_neg_integer()
  def retry_delay(attempt) when is_integer(attempt) and attempt >= 0 do
    retry_delay(attempt, @initial_retry_delay_ms, @max_retry_delay_ms)
  end

  @doc """
  Calculate the retry delay with custom initial and max delays.
  """
  @spec retry_delay(non_neg_integer(), pos_integer(), pos_integer()) :: non_neg_integer()
  def retry_delay(attempt, initial_delay_ms, max_delay_ms)
      when is_integer(attempt) and attempt >= 0 and is_integer(initial_delay_ms) and
             initial_delay_ms > 0 and is_integer(max_delay_ms) and max_delay_ms > 0 do
    base_delay = initial_delay_ms * :math.pow(2, attempt)
    capped_delay = min(base_delay, max_delay_ms)
    jitter = @jitter_min + :rand.uniform() * (@jitter_max - @jitter_min)
    round(capped_delay * jitter)
  end

  def retry_delay(_attempt, _initial_delay_ms, _max_delay_ms), do: 0

  @doc """
  Determine whether a status code is retryable.
  """
  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(408), do: true
  def retryable_status?(409), do: true
  def retryable_status?(429), do: true
  def retryable_status?(status) when status >= 500 and status < 600, do: true
  def retryable_status?(_status), do: false

  @doc """
  Parse Retry-After headers into milliseconds.

  Supports:
    * `retry-after-ms` - milliseconds
    * `retry-after` - seconds
  """
  @spec parse_retry_after(headers(), non_neg_integer()) :: non_neg_integer()
  def parse_retry_after(headers, default_ms \\ @default_retry_after_ms) do
    parse_retry_after_ms(headers) || parse_retry_after_seconds(headers) || default_ms
  end

  @doc """
  Decide whether a response should be retried based on headers and status.
  """
  @spec should_retry?(map() | {integer(), headers()} | integer()) :: boolean()
  def should_retry?(%{status: status} = response) do
    should_retry_status(status, Map.get(response, :headers, []))
  end

  def should_retry?(%{"status" => status} = response) do
    should_retry_status(status, Map.get(response, "headers", []))
  end

  def should_retry?({status, headers}) when is_integer(status) do
    should_retry_status(status, headers)
  end

  def should_retry?(status) when is_integer(status), do: retryable_status?(status)
  def should_retry?(_), do: false

  defp should_retry_status(status, headers) do
    case header_value(headers, "x-should-retry") do
      nil ->
        retryable_status?(status)

      value ->
        case String.downcase(value) do
          "false" -> false
          "true" -> true
          _ -> retryable_status?(status)
        end
    end
  end

  defp parse_retry_after_ms(headers) do
    headers
    |> header_value("retry-after-ms")
    |> parse_integer(:ms)
  end

  defp parse_retry_after_seconds(headers) do
    headers
    |> header_value("retry-after")
    |> parse_integer(:seconds)
  end

  defp parse_integer(nil, _unit), do: nil

  defp parse_integer(value, unit) do
    case Integer.parse(value) do
      {number, _} -> convert_retry_after(number, unit)
      :error -> nil
    end
  end

  defp convert_retry_after(value, :ms), do: value
  defp convert_retry_after(value, :seconds), do: value * 1_000

  defp header_value(headers, target) when is_list(headers) do
    target = String.downcase(target)

    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) == target do
          normalize_header_value(value)
        end

      _ ->
        nil
    end)
  end

  defp header_value(headers, target) when is_map(headers) do
    target = String.downcase(target)

    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == target do
        normalize_header_value(value)
      end
    end)
  end

  defp header_value(_headers, _target), do: nil

  defp normalize_header_value(value) when is_binary(value) do
    String.trim(value)
  end

  defp normalize_header_value(value) do
    value
    |> to_string()
    |> String.trim()
  end
end
