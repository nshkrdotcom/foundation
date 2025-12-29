defmodule Foundation.Retry.RunnerTest do
  use ExUnit.Case, async: true

  alias Foundation.Retry.{Handler, Runner}

  test "retries on errors until success" do
    handler =
      Handler.new(
        max_retries: 5,
        base_delay_ms: 10,
        max_delay_ms: 100,
        jitter_pct: 0.0
      )

    parent = self()

    fun = fn ->
      attempt = Process.get(:attempt, 0)
      Process.put(:attempt, attempt + 1)

      if attempt < 2 do
        {:error, :failed}
      else
        {:ok, :done}
      end
    end

    sleep_fun = fn ms -> send(parent, {:slept, ms}) end

    assert {:ok, :done} =
             Runner.run(fun, handler: handler, sleep_fun: sleep_fun, telemetry_events: %{})

    assert_received {:slept, 10}
    assert_received {:slept, 20}
  end

  test "halts on progress timeout" do
    now = System.monotonic_time(:millisecond)

    handler = %Handler{
      max_retries: 5,
      base_delay_ms: 10,
      max_delay_ms: 100,
      jitter_pct: 0.0,
      progress_timeout_ms: 0,
      attempt: 1,
      last_progress_at: now - 10,
      start_time: now
    }

    assert {:error, :progress_timeout} = Runner.run(fn -> {:ok, :done} end, handler: handler)
  end

  test "halts on max elapsed time before running the function" do
    handler =
      Handler.new(
        max_retries: 1,
        base_delay_ms: 10,
        max_delay_ms: 100,
        jitter_pct: 0.0
      )

    parent = self()

    time_fun = fn :millisecond ->
      call = Process.get(:time_call, 0)
      Process.put(:time_call, call + 1)
      100 + call
    end

    fun = fn ->
      send(parent, :called)
      {:ok, :done}
    end

    assert {:error, :max_elapsed} =
             Runner.run(fun,
               handler: handler,
               max_elapsed_ms: 0,
               time_fun: time_fun
             )

    refute_received :called
  end

  test "uses delay_fun when provided" do
    handler =
      Handler.new(
        max_retries: 1,
        base_delay_ms: 10,
        max_delay_ms: 100,
        jitter_pct: 0.0
      )

    parent = self()

    fun = fn ->
      attempt = Process.get(:attempt, 0)
      Process.put(:attempt, attempt + 1)

      if attempt < 1 do
        {:error, :retry}
      else
        {:ok, :done}
      end
    end

    sleep_fun = fn ms -> send(parent, {:slept, ms}) end
    delay_fun = fn _result, _handler -> 42 end

    assert {:ok, :done} =
             Runner.run(fun,
               handler: handler,
               sleep_fun: sleep_fun,
               delay_fun: delay_fun
             )

    assert_received {:slept, 42}
  end

  test "propagates exceptions when rescue_exceptions is false" do
    handler = Handler.new(max_retries: 0, jitter_pct: 0.0)

    assert_raise RuntimeError, "boom", fn ->
      Runner.run(fn -> raise "boom" end, handler: handler, rescue_exceptions: false)
    end
  end

  test "calls before_attempt for each attempt" do
    handler =
      Handler.new(
        max_retries: 2,
        base_delay_ms: 1,
        max_delay_ms: 1,
        jitter_pct: 0.0
      )

    parent = self()

    fun = fn ->
      attempt = Process.get(:run_attempt, 0)
      Process.put(:run_attempt, attempt + 1)

      if attempt < 1 do
        {:error, :retry}
      else
        {:ok, :done}
      end
    end

    before_attempt = fn attempt -> send(parent, {:before_attempt, attempt}) end
    sleep_fun = fn _ -> :ok end

    assert {:ok, :done} =
             Runner.run(fun,
               handler: handler,
               sleep_fun: sleep_fun,
               before_attempt: before_attempt
             )

    assert_received {:before_attempt, 0}
    assert_received {:before_attempt, 1}
  end

  test "emits telemetry events when configured" do
    event = [:foundation, :retry, :start]
    handler = Handler.new(max_retries: 0, jitter_pct: 0.0)
    parent = self()
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        event,
        fn event_name, measurements, metadata, _config ->
          send(parent, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

    assert {:ok, :done} =
             Runner.run(fn -> {:ok, :done} end,
               handler: handler,
               telemetry_events: %{start: event},
               telemetry_metadata: %{tag: :ok}
             )

    assert_received {:telemetry, ^event, %{system_time: _}, %{attempt: 0, tag: :ok}}

    :telemetry.detach(ref)
  end
end
