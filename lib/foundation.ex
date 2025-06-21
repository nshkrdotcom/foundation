defmodule Foundation do
  @moduledoc """
  Main public API for Foundation layer.

  Provides unified access to all Foundation services including configuration,
  events, telemetry, and error handling. This is the main entry point for
  interacting with the Foundation layer.
  """

  alias Foundation.{Config, ErrorContext, Events, Telemetry}
  alias Foundation.Types.Error

  @doc """
  Initialize the entire Foundation layer.

  Starts all Foundation services in the correct order and ensures
  they are properly configured and ready for use.

  ## Examples

      iex> Foundation.initialize()
      :ok

      iex> Foundation.initialize(config: [debug_mode: true])
      :ok
  """
  @spec initialize(keyword()) :: :ok | {:error, Error.t()}
  def initialize(opts \\ []) do
    with :ok <- Config.initialize(Keyword.get(opts, :config, [])),
         :ok <- Events.initialize(),
         :ok <- Telemetry.initialize() do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Get the status of all Foundation services.

  Returns a map containing the status of each core service.

  ## Examples

      iex> Foundation.status()
      {:ok, %{
        config: %{status: :running, uptime_ms: 12_345},
        events: %{status: :running, events_count: 1000},
        telemetry: %{status: :running, metrics_count: 50}
      }}
  """
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    with {:ok, config_status} <- Config.status(),
         {:ok, events_status} <- Events.status(),
         {:ok, telemetry_status} <- Telemetry.status() do
      {:ok,
       %{
         config: config_status,
         events: events_status,
         telemetry: telemetry_status
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Check if all Foundation services are available and ready.

  ## Examples

      iex> Foundation.available?()
      true
  """
  @spec available?() :: boolean()
  def available?() do
    Config.available?() and Events.available?() and Telemetry.available?()
  end

  @doc """
  Get version information for the Foundation layer.

  ## Examples

      iex> Foundation.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:foundation, :vsn) |> to_string()
  end

  @doc """
  Start Foundation (alias for initialize/1).
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    context = ErrorContext.new(__MODULE__, :start_link, metadata: %{opts: opts})

    ErrorContext.with_context(context, fn ->
      :ok = initialize(opts)
      {:ok, self()}
    end)
  end

  @doc """
  Shutdown the Foundation layer gracefully.

  This stops all Foundation services in reverse order and ensures
  proper cleanup of resources.

  ## Examples

      iex> Foundation.shutdown()
      :ok
  """
  @spec shutdown() :: :ok
  def shutdown do
    # Stop services in reverse order
    # Let the supervision tree handle the actual shutdown
    case Process.whereis(Foundation.Supervisor) do
      nil ->
        :ok

      pid ->
        Supervisor.stop(pid, :normal)
        :ok
    end
  end

  @doc """
  Get comprehensive health information for the Foundation layer.

  Returns detailed health and performance metrics for monitoring.

  ## Examples

      iex> Foundation.health()
      {:ok, %{
        status: :healthy,
        uptime_ms: 3600000,
        services: %{...},
        metrics: %{...}
      }}
  """
  @spec health() :: {:ok, map()} | {:error, Error.t()}
  def health do
    case status() do
      {:ok, service_status} ->
        health_info = %{
          status: determine_overall_health(service_status),
          timestamp: System.monotonic_time(:millisecond),
          services: service_status,
          foundation_available: available?(),
          elixir_version: System.version(),
          otp_release: System.otp_release()
        }

        {:ok, health_info}

      {:error, _} = error ->
        error
    end
  end

  ## Private Functions

  defp determine_overall_health(service_status) do
    all_running =
      service_status
      |> Map.values()
      |> Enum.all?(fn status -> Map.get(status, :status) == :running end)

    if all_running, do: :healthy, else: :degraded
  end
end
