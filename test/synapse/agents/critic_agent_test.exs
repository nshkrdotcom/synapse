defmodule Synapse.Agents.CriticAgentTest do
  use ExUnit.Case, async: true

  import Synapse.TestSupport.AgentHelpers

  alias Synapse.Actions.CriticReview
  alias Synapse.Agents.CriticAgent

  describe "CriticAgent state tracking" do
    test "stores decision fossils and review metadata" do
      agent = CriticAgent.new()

      agent =
        exec_agent_cmd(
          agent,
          {CriticReview, %{code: "IO.puts(:ok)", intent: "print", constraints: []}}
        )

      # Use helper for cleaner assertion
      assert_agent_state(agent, review_count: 1)

      # Extract state for complex assertions
      state = get_agent_state(agent)

      assert [%{confidence: _conf, escalated: _esc, summary: summary} | _] =
               state.decision_fossils

      assert is_binary(summary)
      assert summary != ""
    end

    test "records scar tissue entries for failed attempts" do
      agent = CriticAgent.new()

      {:ok, agent} =
        CriticAgent.record_failure(agent, %{
          reason: :syntax_error,
          details: "Unexpected token",
          remedy: "Ensure parentheses are balanced"
        })

      # Use helper for assertion
      state = get_agent_state(agent)
      assert [%{reason: :syntax_error, details: "Unexpected token"}] = state.scar_tissue
    end

    test "learn_from_correction updates learned patterns without mutating state directly" do
      agent = CriticAgent.new()

      {:ok, updated} =
        CriticAgent.learn_from_correction(agent, %{
          context: %{file: "lib/app.ex"},
          correction: "Prefer pattern matching in function heads"
        })

      # Compare state using helper
      original_state = get_agent_state(agent)
      updated_state = get_agent_state(updated)

      assert updated_state.learned_patterns != original_state.learned_patterns
      assert Enum.count(updated_state.learned_patterns) == 1
    end
  end
end
