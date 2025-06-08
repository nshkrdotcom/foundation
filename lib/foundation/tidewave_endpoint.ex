defmodule Foundation.TidewaveEndpoint do
  @moduledoc """
  Simple endpoint for Tidewave MCP integration in development.
  """

  use Plug.Router

  # Mount Tidewave at the root - it will handle /tidewave/mcp
  plug Tidewave

  plug :match
  plug :dispatch

  match _ do
    send_resp(conn, 404, "Not found")
  end

  def start_link(_opts) do
    Plug.Cowboy.http(__MODULE__, [], port: 4040)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end