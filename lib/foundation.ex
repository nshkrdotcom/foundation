defmodule Foundation do
  @moduledoc """
  Lightweight resilience primitives for Elixir applications.

  Foundation provides backoff, retry orchestration, rate-limit backoff windows,
  circuit breakers, semaphores, and optional telemetry helpers.
  """

  @doc """
  Return the current Foundation version.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:foundation, :vsn) |> to_string()
  end
end
