defmodule Foundation.Repository.Query do
  @moduledoc """
  Query builder for Foundation repositories.

  Provides a composable query interface for ETS-based repositories
  with support for filtering, ordering, and limiting results.

  ## Usage

      query()
      |> where(:status, :eq, :active)
      |> where(:created_at, :gt, yesterday)
      |> order_by(:name, :asc)
      |> limit(10)
      |> all()
  """

  defstruct repository: nil,
            table: nil,
            filters: [],
            order: nil,
            limit: nil,
            offset: nil

  @type t :: %__MODULE__{
          repository: module(),
          table: atom(),
          filters: list(),
          order: {atom(), :asc | :desc} | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil
        }

  @type operator :: :eq | :neq | :gt | :lt | :gte | :lte | :in | :not_in | :like

  @doc """
  Adds a WHERE clause to the query.

  ## Examples

      query()
      |> where(:status, :eq, :active)
      |> where(:age, :gte, 18)
  """
  @spec where(t(), atom(), operator(), term()) :: t()
  def where(%__MODULE__{} = query, field, operator, value) do
    filter = {field, operator, value}
    %{query | filters: query.filters ++ [filter]}
  end

  @doc """
  Adds an ORDER BY clause to the query.

  ## Examples

      query()
      |> order_by(:created_at, :desc)
  """
  @spec order_by(t(), atom(), :asc | :desc) :: t()
  def order_by(%__MODULE__{} = query, field, direction) do
    %{query | order: {field, direction}}
  end

  @doc """
  Adds a LIMIT clause to the query.

  ## Examples

      query()
      |> limit(10)
  """
  @spec limit(t(), pos_integer()) :: t()
  def limit(%__MODULE__{} = query, count) when is_integer(count) and count > 0 do
    %{query | limit: count}
  end

  @doc """
  Adds an OFFSET clause to the query.

  ## Examples

      query()
      |> offset(20)
      |> limit(10)  # Get items 21-30
  """
  @spec offset(t(), non_neg_integer()) :: t()
  def offset(%__MODULE__{} = query, count) when is_integer(count) and count >= 0 do
    %{query | offset: count}
  end

  @doc """
  Executes the query and returns all matching results.

  ## Examples

      {:ok, users} = query() |> where(:active, :eq, true) |> all()
  """
  @spec all(t()) :: {:ok, [map()]} | {:error, term()}
  def all(%__MODULE__{} = query) do
    execute_query(query, :all)
  end

  @doc """
  Executes the query and returns the first matching result.

  ## Examples

      {:ok, user} = query() |> where(:email, :eq, "user@example.com") |> one()
  """
  @spec one(t()) :: {:ok, map()} | {:error, :not_found}
  def one(%__MODULE__{} = query) do
    execute_query(query, :one)
  end

  @doc """
  Executes the query and returns the count of matching results.

  ## Examples

      {:ok, count} = query() |> where(:status, :eq, :active) |> count()
  """
  @spec count(t()) :: {:ok, non_neg_integer()}
  def count(%__MODULE__{} = query) do
    execute_query(query, :count)
  end

  # Private functions

  defp execute_query(%__MODULE__{} = query, return_type) do
    # Get all records from ETS
    all_records = :ets.tab2list(query.table)

    # Apply filters
    filtered = apply_filters(all_records, query.filters)

    # Apply ordering
    ordered = apply_ordering(filtered, query.order)

    # Apply offset and limit
    paginated = apply_pagination(ordered, query.offset, query.limit)

    # Extract values from ETS format
    results = Enum.map(paginated, fn {_key, value, _metadata} -> value end)

    # Return based on type
    case return_type do
      :all ->
        {:ok, results}

      :one ->
        case results do
          [first | _] -> {:ok, first}
          [] -> {:error, :not_found}
        end

      :count ->
        {:ok, length(filtered)}
    end
  end

  defp apply_filters(records, filters) do
    Enum.filter(records, fn {_key, value, _metadata} ->
      Enum.all?(filters, fn {field, operator, expected} ->
        actual = Map.get(value, field)
        apply_operator(actual, operator, expected)
      end)
    end)
  end

  defp apply_operator(actual, :eq, expected), do: actual == expected
  defp apply_operator(actual, :neq, expected), do: actual != expected
  defp apply_operator(actual, :gt, expected), do: actual > expected
  defp apply_operator(actual, :lt, expected), do: actual < expected
  defp apply_operator(actual, :gte, expected), do: actual >= expected
  defp apply_operator(actual, :lte, expected), do: actual <= expected
  defp apply_operator(actual, :in, expected) when is_list(expected), do: actual in expected
  defp apply_operator(actual, :not_in, expected) when is_list(expected), do: actual not in expected

  defp apply_operator(actual, :like, pattern) when is_binary(actual) and is_binary(pattern) do
    regex =
      pattern
      |> String.replace("%", ".*")
      |> String.replace("_", ".")
      |> Regex.compile!()

    Regex.match?(regex, actual)
  end

  defp apply_operator(_, _, _), do: false

  defp apply_ordering(records, nil), do: records

  defp apply_ordering(records, {field, direction}) do
    Enum.sort_by(
      records,
      fn {_key, value, _metadata} ->
        Map.get(value, field)
      end,
      direction
    )
  end

  defp apply_pagination(records, nil, nil), do: records

  defp apply_pagination(records, offset, limit) do
    records
    |> maybe_drop(offset)
    |> maybe_take(limit)
  end

  defp maybe_drop(records, nil), do: records
  defp maybe_drop(records, offset), do: Enum.drop(records, offset)

  defp maybe_take(records, nil), do: records
  defp maybe_take(records, limit), do: Enum.take(records, limit)
end
