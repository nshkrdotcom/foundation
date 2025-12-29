defmodule Foundation.Semaphore.WeightedTest do
  use ExUnit.Case, async: true

  alias Foundation.Semaphore.Weighted

  describe "acquire and release" do
    test "allows budget to go negative for in-flight work" do
      {:ok, pid} = Weighted.start_link(max_weight: 10)

      assert :ok = Weighted.acquire(pid, 12)
      assert :ok = Weighted.release(pid, 5)
      assert :ok = Weighted.release(pid, 7)
    end

    test "blocks when budget is negative and resumes on release" do
      {:ok, pid} = Weighted.start_link(max_weight: 10)

      assert :ok = Weighted.acquire(pid, 15)

      task = Task.async(fn -> Weighted.acquire(pid, 1) end)

      assert nil == Task.yield(task, 20)

      assert :ok = Weighted.release(pid, 5)

      assert {:ok, :ok} == Task.yield(task, 100)
    end
  end

  describe "try_acquire/2" do
    test "returns unavailable when budget is negative" do
      {:ok, pid} = Weighted.start_link(max_weight: 10)
      assert :ok = Weighted.acquire(pid, 15)

      assert {:error, :unavailable} = Weighted.try_acquire(pid, 1)
    end

    test "acquires when budget is non-negative" do
      {:ok, pid} = Weighted.start_link(max_weight: 10)
      assert :ok = Weighted.try_acquire(pid, 3)
    end
  end

  describe "with_acquire/3" do
    test "releases after executing the function" do
      {:ok, pid} = Weighted.start_link(max_weight: 10)

      assert :ok =
               Weighted.with_acquire(pid, 5, fn ->
                 :ok
               end)

      assert :ok = Weighted.try_acquire(pid, 10)
    end
  end
end
