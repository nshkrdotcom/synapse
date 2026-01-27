defmodule Synapse.CoordinationStateTest do
  use ExUnit.Case, async: true

  alias Synapse.CoordinationState

  describe "struct" do
    test "initial state created with correct defaults" do
      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator,
            strategy: :parallel,
            consensus_algorithm: :weighted_vote,
            weights: %{},
            termination_conditions: []
          },
          300_000
        )

      assert state.request_id == "req-123"
      assert state.coordinator_spec.id == :test_coordinator
      assert state.timeout_remaining_ms == 300_000
    end

    test "iteration counter starts at 0" do
      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator
          },
          300_000
        )

      assert state.iteration == 0
    end

    test "agent states map initialized empty" do
      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator
          },
          300_000
        )

      assert state.agent_states == %{}
    end

    test "consensus score starts at nil" do
      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator
          },
          300_000
        )

      assert state.consensus_score == nil
    end

    test "timeout remaining initialized from request" do
      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator
          },
          250_000
        )

      assert state.timeout_remaining_ms == 250_000
    end

    test "timestamps set correctly" do
      before = DateTime.utc_now()

      state =
        CoordinationState.new(
          "req-123",
          %Synapse.CoordinatorSpec{
            id: :test_coordinator
          },
          300_000
        )

      after_time = DateTime.utc_now()

      assert DateTime.compare(state.created_at, before) in [:eq, :gt]
      assert DateTime.compare(state.created_at, after_time) in [:eq, :lt]
      assert state.last_updated_at == state.created_at
    end
  end
end
