defmodule MockWorkerTest do
  use ExUnit.Case

  test "MockWorker can be started" do
    {:ok, pid} = MockWorker.start_link([])
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "MockWorker responds to ping" do
    {:ok, pid} = MockWorker.start_link([])
    assert :pong = GenServer.call(pid, :ping)
    GenServer.stop(pid)
  end
end
