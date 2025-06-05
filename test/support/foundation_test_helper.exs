defmodule FoundationTestHelper do
  @moduledoc """
  Modern test helper for Foundation layer services.

  Works with the Registry-based service architecture to provide
  clean test environments without conflicts.
  """

  alias Foundation.Services.{ConfigServer, EventStore, TelemetryService}

  @doc """
  Set up test environment for Foundation services.

  Simply ensures services are available and sets test mode.
  Services are already started by the Application supervision tree.
  """
  def setup_foundation_test do
    # Set test mode
    Application.put_env(:foundation, :test_mode, true)

    # Reset service states to clean defaults
    reset_service_states()

    :ok
  end

  @doc """
  Clean up test environment after Foundation service tests.
  """
  def cleanup_foundation_test do
    # Reset states again for next test
    reset_service_states()

    # Remove test mode
    Application.delete_env(:foundation, :test_mode)

    :ok
  end

  @doc """
  Reset all service states to clean defaults.

  Works with services that support reset_state/0.
  """
  def reset_service_states do
    # Only reset if services are available and support reset
    if ConfigServer.available?() do
      try do
        ConfigServer.reset_state()
      rescue
        _ -> :ok
      end
    end

    if EventStore.available?() do
      try do
        EventStore.reset_state()
      rescue
        _ -> :ok
      end
    end

    if TelemetryService.available?() do
      try do
        TelemetryService.reset_state()
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Wait for all Foundation services to be available.

  Returns quickly since services should already be started
  by the Application supervision tree.
  """
  def wait_for_services(timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(deadline)
  end

  defp wait_loop(deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      if services_available?() do
        :ok
      else
        Process.sleep(10)
        wait_loop(deadline)
      end
    end
  end

  defp services_available? do
    ConfigServer.available?() and
      EventStore.available?() and
      TelemetryService.available?()
  end
end
