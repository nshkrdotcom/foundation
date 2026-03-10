defmodule Foundation.Retry.HTTP do
  @moduledoc """
  HTTP retry helpers with generic status, method, and Retry-After parsing helpers.

  Provides retry delay calculation, status classification, and Retry-After parsing.
  """

  @initial_retry_delay_ms 500
  @max_retry_delay_ms 10_000
  @jitter_min 0.75
  @jitter_max 1.0
  @default_retry_after_ms 1_000

  @type headers :: [{String.t(), String.t()}] | map()
  @type method :: atom() | String.t()
  @type retryable_statuses_by_method ::
          keyword([integer()]) | %{optional(method() | :all) => [integer()]}

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
  Determine whether a status code is retryable for the given method under
  caller-provided method rules.

  Rules may be provided as a map or keyword list keyed by HTTP method or `:all`.
  """
  @spec retryable_status_for_method?(integer(), method(), retryable_statuses_by_method()) ::
          boolean()
  def retryable_status_for_method?(status, method, rules) when is_integer(status) do
    normalized_method = normalize_method(method)

    rules
    |> normalize_retryable_status_rules()
    |> Enum.any?(fn {rule_method, statuses} ->
      (rule_method == :all or rule_method == normalized_method) and status in statuses
    end)
  end

  def retryable_status_for_method?(_status, _method, _rules), do: false

  @doc """
  Parse Retry-After headers into milliseconds.

  Supports:
    * `retry-after-ms` - milliseconds
    * `retry-after` - delta-seconds
    * `retry-after` - HTTP-date
  """
  @spec parse_retry_after(headers(), non_neg_integer()) :: non_neg_integer()
  def parse_retry_after(headers, default_ms \\ @default_retry_after_ms) do
    parse_retry_after_ms(headers) || parse_retry_after_value(headers) || default_ms
  end

  @doc """
  Decide whether a response should be retried based on headers and status.
  """
  @spec should_retry?(map() | {integer(), headers()} | integer()) :: boolean()
  def should_retry?(%{status: status} = response) do
    should_retry_status(status, Map.get(response, :headers, []), &retryable_status?/1)
  end

  def should_retry?(%{"status" => status} = response) do
    should_retry_status(status, Map.get(response, "headers", []), &retryable_status?/1)
  end

  def should_retry?({status, headers}) when is_integer(status) do
    should_retry_status(status, headers, &retryable_status?/1)
  end

  def should_retry?(status) when is_integer(status), do: retryable_status?(status)
  def should_retry?(_), do: false

  @doc """
  Decide whether a response should be retried based on the given method, headers,
  and caller-provided method rules.
  """
  @spec should_retry_for_method?(
          method(),
          map() | {integer(), headers()} | integer(),
          retryable_statuses_by_method()
        ) :: boolean()
  def should_retry_for_method?(method, %{status: status} = response, rules) do
    should_retry_status(status, Map.get(response, :headers, []), fn status ->
      retryable_status_for_method?(status, method, rules)
    end)
  end

  def should_retry_for_method?(method, %{"status" => status} = response, rules) do
    should_retry_status(status, Map.get(response, "headers", []), fn status ->
      retryable_status_for_method?(status, method, rules)
    end)
  end

  def should_retry_for_method?(method, {status, headers}, rules) when is_integer(status) do
    should_retry_status(status, headers, fn status ->
      retryable_status_for_method?(status, method, rules)
    end)
  end

  def should_retry_for_method?(method, status, rules) when is_integer(status) do
    retryable_status_for_method?(status, method, rules)
  end

  def should_retry_for_method?(_method, _response, _rules), do: false

  defp should_retry_status(status, headers, retryable_status?) do
    case header_value(headers, "x-should-retry") do
      nil ->
        retryable_status?.(status)

      value ->
        case String.downcase(value) do
          "false" -> false
          "true" -> true
          _ -> retryable_status?.(status)
        end
    end
  end

  defp parse_retry_after_ms(headers) do
    headers
    |> header_value("retry-after-ms")
    |> parse_integer(:ms)
  end

  defp parse_retry_after_value(headers) do
    case header_value(headers, "retry-after") do
      nil ->
        nil

      value ->
        parse_integer(value, :seconds) || parse_http_date(value)
    end
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

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{_, _, _}, {_, _, _}} = datetime ->
        retry_after_ms =
          (:calendar.datetime_to_gregorian_seconds(datetime) -
             :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())) * 1_000

        max(retry_after_ms, 0)

      _ ->
        nil
    end
  end

  defp normalize_retryable_status_rules(rules) when is_list(rules) or is_map(rules) do
    Enum.flat_map(rules, fn
      {method, statuses} when is_list(statuses) ->
        case normalize_rule_method(method) do
          nil -> []
          normalized_method -> [{normalized_method, Enum.filter(statuses, &is_integer/1)}]
        end

      _ ->
        []
    end)
  end

  defp normalize_retryable_status_rules(_rules), do: []

  defp normalize_rule_method(:all), do: :all
  defp normalize_rule_method(method), do: normalize_method(method)

  defp normalize_method(method) when is_atom(method), do: method

  defp normalize_method(method) when is_binary(method) do
    case String.downcase(String.trim(method)) do
      "delete" -> :delete
      "get" -> :get
      "head" -> :head
      "options" -> :options
      "patch" -> :patch
      "post" -> :post
      "put" -> :put
      _ -> nil
    end
  end

  defp normalize_method(_method), do: nil

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
