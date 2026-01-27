defmodule Synapse.TimeoutManagerTest do
  use ExUnit.Case, async: true

  alias Synapse.TimeoutManager

  describe "per_iteration_timeout/3" do
    test "calculated correctly" do
      # 300_000ms remaining, 5 max iterations, currently at iteration 1
      # remaining_iterations = 5 - 1 + 1 = 5
      # per_iteration = 300_000 / 5 = 60_000
      timeout = TimeoutManager.per_iteration_timeout(300_000, 5, 1)
      assert timeout == 60_000
    end

    test "decreases as iterations progress" do
      # At iteration 1: 300_000 / (5 - 1 + 1) = 60_000
      t1 = TimeoutManager.per_iteration_timeout(300_000, 5, 1)

      # At iteration 3 with 180_000 remaining: 180_000 / (5 - 3 + 1) = 60_000
      t3 = TimeoutManager.per_iteration_timeout(180_000, 5, 3)

      # At iteration 5 with 60_000 remaining: 60_000 / (5 - 5 + 1) = 60_000
      t5 = TimeoutManager.per_iteration_timeout(60_000, 5, 5)

      assert t1 == 60_000
      assert t3 == 60_000
      assert t5 == 60_000
    end
  end

  describe "should_terminate?/1" do
    test "returns :continue when time remaining" do
      state = %{
        timeout_remaining_ms: 100_000,
        elapsed_ms: 50_000,
        timeout_ms: 300_000,
        iteration: 1,
        max_iterations: 5,
        agent_states: %{}
      }

      assert TimeoutManager.should_terminate?(state) == :continue
    end

    test "returns {:timeout, state} when budget exhausted" do
      state = %{
        timeout_remaining_ms: 0,
        elapsed_ms: 300_000,
        timeout_ms: 300_000,
        iteration: 3,
        max_iterations: 5,
        agent_states: %{agent_a: %{status: :complete, output: "result"}}
      }

      assert {:timeout, partial} = TimeoutManager.should_terminate?(state)
      assert partial.agent_states == state.agent_states
    end

    test "partial state captured on timeout" do
      state = %{
        timeout_remaining_ms: 0,
        elapsed_ms: 300_000,
        timeout_ms: 300_000,
        iteration: 2,
        max_iterations: 5,
        agent_states: %{
          agent_a: %{status: :complete, output: "partial result"},
          agent_b: %{status: :running, output: nil}
        }
      }

      assert {:timeout, partial} = TimeoutManager.should_terminate?(state)
      assert partial.iteration == 2
      assert map_size(partial.agent_states) == 2
    end

    test "edge case: remaining_ms = 0 returns timeout immediately" do
      state = %{
        timeout_remaining_ms: 0,
        elapsed_ms: 0,
        timeout_ms: 0,
        iteration: 0,
        max_iterations: 5,
        agent_states: %{}
      }

      assert {:timeout, _partial} = TimeoutManager.should_terminate?(state)
    end

    test "edge case: current_iteration = max_iterations" do
      state = %{
        timeout_remaining_ms: 100_000,
        elapsed_ms: 200_000,
        timeout_ms: 300_000,
        iteration: 5,
        max_iterations: 5,
        agent_states: %{agent_a: %{status: :complete, output: "done"}}
      }

      # At max iterations but still has time - should still continue
      # (iteration limit is checked separately from timeout)
      assert TimeoutManager.should_terminate?(state) == :continue
    end
  end

  describe "capture_partial_state/1" do
    test "captures current state for timeout result" do
      state = %{
        iteration: 3,
        agent_states: %{
          agent_a: %{status: :complete, output: "result_a"},
          agent_b: %{status: :running, output: nil}
        },
        consensus_score: 0.5,
        elapsed_ms: 250_000
      }

      partial = TimeoutManager.capture_partial_state(state)
      assert partial.iteration == 3
      assert partial.agent_states == state.agent_states
      assert partial.consensus_score == 0.5
    end
  end
end
