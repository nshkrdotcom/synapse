defmodule Synapse.Agents.CriticAgentWithHelpersTest do
  use ExUnit.Case, async: true

  import Synapse.TestSupport.AgentHelpers

  alias Synapse.Actions.CriticReview
  alias Synapse.Agents.CriticAgent

  describe "CriticAgent with AgentHelpers" do
    test "stores decision fossils using cleaner assertions" do
      agent = CriticAgent.new()

      {:ok, agent, _} =
        CriticAgent.cmd(
          agent,
          {CriticReview, %{code: "IO.puts(:ok)", intent: "print", constraints: []}}
        )

      # Use helper for cleaner assertions
      assert_agent_state(agent, review_count: 1)

      # Verify decision fossils structure
      state = get_agent_state(agent)
      assert [%{confidence: conf, summary: summary}] = state.decision_fossils
      assert is_float(conf)
      assert is_binary(summary)
      assert summary != ""
    end

    test "maintains circular buffer for review history" do
      agent = CriticAgent.new()

      # Execute multiple reviews
      agent =
        Enum.reduce(1..150, agent, fn i, acc_agent ->
          {:ok, new_agent, _} =
            CriticAgent.cmd(
              acc_agent,
              {CriticReview, %{code: "code_#{i}", intent: "test", constraints: []}}
            )

          new_agent
        end)

      # Verify circular buffer limit (100 max)
      assert_agent_state(agent, review_count: 150)

      state = get_agent_state(agent)
      assert Enum.count(state.review_history) == 100
      assert Enum.count(state.decision_fossils) <= 50
    end

    test "learned patterns accumulate over corrections" do
      agent = CriticAgent.new()

      # Learn from correction
      {:ok, agent} =
        CriticAgent.learn_from_correction(agent, %{
          context: %{file: "lib/app.ex"},
          correction: "Prefer pattern matching over case statements"
        })

      state = get_agent_state(agent)
      assert Enum.count(state.learned_patterns) == 1

      # Check the structure of learned patterns
      assert [
               %{
                 pattern: _pattern_key,
                 count: 1,
                 examples: [
                   %{
                     context: %{file: "lib/app.ex"},
                     correction: "Prefer pattern matching over case statements"
                   }
                 ]
               }
             ] = state.learned_patterns
    end

    test "scar tissue records failures for learning" do
      agent = CriticAgent.new()

      {:ok, agent} =
        CriticAgent.record_failure(agent, %{
          reason: :syntax_error,
          details: "Unexpected token",
          remedy: "Balance parentheses"
        })

      state = get_agent_state(agent)
      assert [%{reason: :syntax_error, details: "Unexpected token"}] = state.scar_tissue
    end

    test "exec_agent_cmd helper reduces boilerplate" do
      agent = CriticAgent.new()

      # Use helper instead of manual {:ok, agent, _} matching
      agent =
        exec_agent_cmd(agent, {CriticReview, %{code: "test", intent: "test", constraints: []}})

      assert_agent_state(agent, review_count: 1)
      assert_agent_state_has_key(agent, :decision_fossils)
    end

    test "exec_agent_cmds executes multiple commands" do
      agent = CriticAgent.new()

      agent =
        exec_agent_cmds(agent, [
          {CriticReview, %{code: "code1", intent: "test1", constraints: []}},
          {CriticReview, %{code: "code2", intent: "test2", constraints: []}},
          {CriticReview, %{code: "code3", intent: "test3", constraints: []}}
        ])

      assert_agent_state(agent, review_count: 3)

      state = get_agent_state(agent)
      assert Enum.count(state.review_history) == 3
    end

    test "assert_agent_state works with map syntax" do
      agent = CriticAgent.new()

      agent =
        exec_agent_cmd(agent, {CriticReview, %{code: "test", intent: "test", constraints: []}})

      # Map syntax
      assert_agent_state(agent, %{
        review_count: 1,
        learned_patterns: []
      })
    end
  end
end
