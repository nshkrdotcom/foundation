defmodule Foundation.TelemetryTest do
  use ExUnit.Case, async: true

  alias Foundation.Telemetry

  defmodule Support do
    @key {__MODULE__, :pid}

    def put_pid(pid), do: :persistent_term.put(@key, pid)
    def pid, do: :persistent_term.get(@key, nil)
  end

  defp attach(event) do
    handler_id = {__MODULE__, make_ref()}
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn event_name, measurements, metadata, _config ->
          send(parent, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    handler_id
  end

  defp load_fake_reporter do
    unless Code.ensure_loaded?(TelemetryReporter) do
      Code.compile_string("""
      defmodule TelemetryReporter do
        def __foundation_fake__, do: true

        def start_link(opts) do
          send(Foundation.TelemetryTest.Support.pid(), {:start_link, opts})
          {:ok, self()}
        end

        def log(reporter, name, data, severity) do
          send(Foundation.TelemetryTest.Support.pid(), {:log, reporter, name, data, severity})
          :ok
        end
      end

      defmodule TelemetryReporter.TelemetryAdapter do
        def __foundation_fake__, do: true

        def attach_many(opts) do
          send(Foundation.TelemetryTest.Support.pid(), {:attach_many, opts})
          :fake_handler
        end

        def detach(handler_id) do
          send(Foundation.TelemetryTest.Support.pid(), {:detach, handler_id})
          :ok
        end
      end
      """)
    end
  end

  defp unload_fake_reporter do
    for mod <- [TelemetryReporter.TelemetryAdapter, TelemetryReporter] do
      if Code.ensure_loaded?(mod) and function_exported?(mod, :__foundation_fake__, 0) do
        :code.purge(mod)
        :code.delete(mod)
      end
    end
  end

  test "execute/3 emits a telemetry event" do
    event = [:foundation, :execute]
    attach(event)

    assert :ok = Telemetry.execute(event, %{count: 1}, %{tag: :ok})
    assert_received {:telemetry, ^event, %{count: 1}, %{tag: :ok}}
  end

  test "measure/4 emits stop events with duration metadata" do
    event = [:foundation, :measure]
    stop_event = event ++ [:stop]
    attach(stop_event)

    assert :ok =
             Telemetry.measure(event, %{label: :ok}, fn ->
               :ok
             end)

    assert_received {:telemetry, ^stop_event, measurements, %{label: :ok}}
    assert %{duration: duration, time_unit: :microsecond} = measurements
    assert is_integer(duration)
    assert duration >= 0
  end

  test "measure/4 emits exception events and reraises" do
    event = [:foundation, :measure]
    exception_event = event ++ [:exception]
    attach(exception_event)

    assert_raise RuntimeError, "boom", fn ->
      Telemetry.measure(event, %{label: :error}, fn ->
        raise "boom"
      end)
    end

    assert_received {:telemetry, ^exception_event, measurements, metadata}
    assert %{duration: duration, time_unit: :microsecond} = measurements
    assert is_integer(duration)
    assert %RuntimeError{message: "boom"} = metadata.error
  end

  test "reporter helpers handle missing dependency and delegate when available" do
    unload_fake_reporter()

    if Code.ensure_loaded?(TelemetryReporter) do
      :ok
    else
      assert {:error, :missing_dependency} = Telemetry.start_reporter([])
      assert {:error, :missing_dependency} = Telemetry.log(:reporter, "event")
      assert {:error, :missing_dependency} = Telemetry.attach_reporter(reporter: :r, events: [])
      assert {:error, :missing_dependency} = Telemetry.detach_reporter(:handler)

      Support.put_pid(self())
      load_fake_reporter()

      on_exit(fn -> unload_fake_reporter() end)

      assert {:ok, _pid} = Telemetry.start_reporter(test: true)
      assert_received {:start_link, [test: true]}

      assert :ok = Telemetry.log(:reporter, "event", %{ok: true}, :info)
      assert_received {:log, :reporter, "event", %{ok: true}, :info}

      assert {:ok, :fake_handler} =
               Telemetry.attach_reporter(reporter: :reporter, events: [[:foundation, :event]])

      assert_received {:attach_many, [reporter: :reporter, events: [[:foundation, :event]]]}

      assert :ok = Telemetry.detach_reporter(:fake_handler)
      assert_received {:detach, :fake_handler}
    end
  end
end
