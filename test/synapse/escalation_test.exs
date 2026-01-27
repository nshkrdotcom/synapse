defmodule Synapse.EscalationTest do
  use ExUnit.Case, async: true

  alias Synapse.Escalation

  describe "build_escalation_request/2" do
    test "includes all required fields" do
      state = %{
        agent_states: %{
          reviewer_agent: %{status: :complete, output: %{approved: true, position: :approve}},
          security_agent: %{status: :complete, output: %{approved: false, position: :reject}}
        },
        consensus_score: 0.4,
        iteration: 5,
        request: %{
          synapse_spec: %{
            escalation_policy: :on_no_consensus
          }
        }
      }

      request = Escalation.build_escalation_request(state, :no_consensus)

      assert Map.has_key?(request, :type)
      assert Map.has_key?(request, :context)
      assert Map.has_key?(request, :options)
      assert Map.has_key?(request, :agent_positions)
      assert Map.has_key?(request, :disagreement_summary)
    end

    test "escalation type derived from escalation_policy" do
      state = %{
        agent_states: %{},
        consensus_score: 0.0,
        iteration: 1,
        request: %{synapse_spec: %{escalation_policy: :always_escalate}}
      }

      request = Escalation.build_escalation_request(state, :always_escalate)
      assert request.type == :human_decision
    end

    test "agent positions extracted from coordination state" do
      state = %{
        agent_states: %{
          agent_a: %{status: :complete, output: %{position: :approve}},
          agent_b: %{status: :complete, output: %{position: :reject}}
        },
        consensus_score: 0.5,
        iteration: 3,
        request: %{synapse_spec: %{escalation_policy: :on_no_consensus}}
      }

      request = Escalation.build_escalation_request(state, :no_consensus)

      assert Map.has_key?(request.agent_positions, :agent_a)
      assert Map.has_key?(request.agent_positions, :agent_b)
    end

    test "disagreement summary generated correctly" do
      state = %{
        agent_states: %{
          agent_a: %{status: :complete, output: %{position: :approve, reason: "Looks good"}},
          agent_b: %{status: :complete, output: %{position: :reject, reason: "Security concern"}}
        },
        consensus_score: 0.5,
        iteration: 5,
        request: %{synapse_spec: %{escalation_policy: :on_no_consensus}}
      }

      request = Escalation.build_escalation_request(state, :no_consensus)

      assert is_binary(request.disagreement_summary)
      assert String.length(request.disagreement_summary) > 0
    end

    test "options derived from agent positions" do
      state = %{
        agent_states: %{
          agent_a: %{status: :complete, output: %{position: :approve}},
          agent_b: %{status: :complete, output: %{position: :reject}}
        },
        consensus_score: 0.5,
        iteration: 3,
        request: %{synapse_spec: %{escalation_policy: :on_no_consensus}}
      }

      request = Escalation.build_escalation_request(state, :no_consensus)

      assert is_list(request.options)
      assert :approve in request.options
      assert :reject in request.options
    end

    test "context summarizes the coordination attempt" do
      state = %{
        agent_states: %{
          agent_a: %{status: :complete, output: %{position: :approve}}
        },
        consensus_score: 0.4,
        iteration: 5,
        request: %{synapse_spec: %{escalation_policy: :on_no_consensus}}
      }

      request = Escalation.build_escalation_request(state, :no_consensus)

      assert is_binary(request.context)
      assert String.length(request.context) > 0
    end
  end

  describe "determine_escalation_type/1" do
    test "maps :always_escalate to :human_decision" do
      assert Escalation.determine_escalation_type(:always_escalate) == :human_decision
    end

    test "maps :human_approval to :human_decision (synonym)" do
      assert Escalation.determine_escalation_type(:human_approval) == :human_decision
    end

    test "maps :on_no_consensus to :human_decision" do
      assert Escalation.determine_escalation_type(:on_no_consensus) == :human_decision
    end

    test "maps :on_failure to :policy_exception" do
      assert Escalation.determine_escalation_type(:on_failure) == :policy_exception
    end

    test "maps :never_escalate to :policy_exception" do
      assert Escalation.determine_escalation_type(:never_escalate) == :policy_exception
    end

    test "maps unknown to :policy_exception" do
      assert Escalation.determine_escalation_type(:unknown) == :policy_exception
    end
  end
end
