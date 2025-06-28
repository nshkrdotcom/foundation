defmodule Foundation.AsyncTestHelpers do
  @moduledoc """
  Helpers for testing asynchronous operations without using Process.sleep.

  Based on the guidelines in docs20250627/042_SLEEP.md
  """

  @doc """
  Polls a function until it returns a truthy value or a timeout is reached.

  This is an acceptable replacement for `Process.sleep/1` in tests for
  complex async scenarios.
  """
  def wait_for(fun, timeout \\ 1_000, interval \\ 10) do
    start_time = System.monotonic_time(:millisecond)

    check_fun = fn check_fun ->
      case fun.() do
        result when result != nil and result != false ->
          result

        _ ->
          handle_wait_timeout(check_fun, start_time, timeout, interval)
      end
    end

    check_fun.(check_fun)
  end

  defp handle_wait_timeout(check_fun, start_time, timeout, interval) do
    if System.monotonic_time(:millisecond) - start_time > timeout do
      ExUnit.Assertions.flunk("wait_for timed out after #{timeout}ms")
    else
      Process.sleep(interval)
      check_fun.(check_fun)
    end
  end

  @doc """
  Waits for a telemetry event to be emitted.

  ## Example

      assert_telemetry_event [:my_app, :event], %{count: 1} do
        MyApp.trigger_event()
      end
  """
  defmacro assert_telemetry_event(
             event_name,
             expected_measurements \\ %{},
             expected_metadata \\ %{},
             do: block
           ) do
    quote do
      test_pid = self()
      ref = make_ref()

      handler = fn ^unquote(event_name), measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, measurements, metadata})
      end

      :telemetry.attach({__MODULE__, unquote(event_name), ref}, unquote(event_name), handler, nil)

      try do
        # Execute the block that should trigger the event
        unquote(block)

        # Wait for the event
        assert_receive {:telemetry_event, ^ref, measurements, metadata}, 1000

        # Verify measurements if provided
        for {key, expected_value} <- unquote(expected_measurements) do
          assert Map.get(measurements, key) == expected_value
        end

        # Verify metadata if provided
        for {key, expected_value} <- unquote(expected_metadata) do
          assert Map.get(metadata, key) == expected_value
        end

        {measurements, metadata}
      after
        :telemetry.detach({__MODULE__, unquote(event_name), ref})
      end
    end
  end

  @doc """
  Starts a process and waits for it to send a ready signal.

  ## Example

      {:ok, pid} = start_and_wait_ready(fn ->
        MyWorker.start_link(parent: self())
      end)
  """
  def start_and_wait_ready(start_fun, timeout \\ 5_000) do
    case start_fun.() do
      {:ok, pid} = result ->
        receive do
          {:ready, ^pid} -> result
          {atom, ^pid} when atom in [:initialized, :started, :worker_ready] -> result
        after
          timeout ->
            Process.exit(pid, :kill)
            {:error, :initialization_timeout}
        end

      error ->
        error
    end
  end

  @doc """
  Ensures a process has processed all messages in its mailbox.

  Useful for testing that a GenServer has handled all pending messages
  before making assertions about its state.
  """
  def sync_with_process(pid, timeout \\ 1_000) do
    ref = make_ref()
    GenServer.call(pid, {:sync, ref}, timeout)
    ref
  end
end
