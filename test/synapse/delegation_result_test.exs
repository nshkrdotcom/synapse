defmodule Synapse.DelegationResultTest do
  use ExUnit.Case, async: true

  alias Synapse.DelegationResult

  describe "struct" do
    test "valid struct with status :success and outputs" do
      result = %DelegationResult{
        status: :success,
        outputs: %{review_result: %{approved: true}},
        telemetry: %{
          iterations: 3,
          total_tokens: 15000,
          total_cost_usd: Decimal.new("0.45"),
          agents_invoked: [:reviewer_agent, :security_agent],
          consensus_score: 0.9
        }
      }

      assert result.status == :success
      assert result.outputs.review_result.approved == true
      assert result.telemetry.iterations == 3
      assert result.telemetry.consensus_score == 0.9
    end

    test "valid struct with status :escalate and escalation_request" do
      result = %DelegationResult{
        status: :escalate,
        reason: :no_consensus,
        escalation_request: %{
          type: :human_decision,
          context: "Agents disagree on security",
          options: [:approve, :reject, :request_changes],
          agent_positions: %{
            reviewer_agent: :approve,
            security_agent: :reject
          },
          disagreement_summary: "Security agent flagged potential injection"
        },
        partial_outputs: %{review_result: %{approved: :undecided}},
        telemetry: %{
          iterations: 5,
          total_tokens: 25000,
          total_cost_usd: Decimal.new("0.75"),
          agents_invoked: [:reviewer_agent, :security_agent],
          consensus_score: 0.4
        }
      }

      assert result.status == :escalate
      assert result.reason == :no_consensus
      assert result.escalation_request.type == :human_decision
      assert result.escalation_request.options == [:approve, :reject, :request_changes]
      assert result.escalation_request.agent_positions.reviewer_agent == :approve
    end

    test "valid struct with status :timeout and partial_outputs" do
      result = %DelegationResult{
        status: :timeout,
        reason: :consensus_timeout,
        partial_outputs: %{partial: "data"},
        telemetry: %{
          iterations: 2,
          total_tokens: 8000,
          total_cost_usd: Decimal.new("0.25"),
          agents_invoked: [:reviewer_agent],
          consensus_score: nil
        }
      }

      assert result.status == :timeout
      assert result.partial_outputs.partial == "data"
      assert result.telemetry.consensus_score == nil
    end

    test "valid struct with status :error and reason" do
      result = %DelegationResult{
        status: :error,
        reason: :agent_failure,
        telemetry: %{
          iterations: 0,
          total_tokens: 0,
          total_cost_usd: Decimal.new("0"),
          agents_invoked: [],
          consensus_score: nil
        }
      }

      assert result.status == :error
      assert result.reason == :agent_failure
    end

    test "telemetry data contains all required fields" do
      result = %DelegationResult{
        status: :success,
        outputs: %{},
        telemetry: %{
          iterations: 1,
          total_tokens: 5000,
          total_cost_usd: Decimal.new("0.15"),
          agents_invoked: [:reviewer_agent],
          consensus_score: 1.0
        }
      }

      telemetry = result.telemetry
      assert Map.has_key?(telemetry, :iterations)
      assert Map.has_key?(telemetry, :total_tokens)
      assert Map.has_key?(telemetry, :total_cost_usd)
      assert Map.has_key?(telemetry, :agents_invoked)
      assert Map.has_key?(telemetry, :consensus_score)
    end

    test "escalation request contains all required fields when present" do
      result = %DelegationResult{
        status: :escalate,
        escalation_request: %{
          type: :human_decision,
          context: "Disagreement context",
          options: [:approve, :reject],
          agent_positions: %{agent_a: :approve, agent_b: :reject},
          disagreement_summary: "Summary of disagreement"
        },
        telemetry: %{
          iterations: 5,
          total_tokens: 20000,
          total_cost_usd: Decimal.new("0.60"),
          agents_invoked: [:agent_a, :agent_b],
          consensus_score: 0.3
        }
      }

      esc = result.escalation_request
      assert Map.has_key?(esc, :type)
      assert Map.has_key?(esc, :context)
      assert Map.has_key?(esc, :options)
      assert Map.has_key?(esc, :agent_positions)
      assert Map.has_key?(esc, :disagreement_summary)
    end
  end

  describe "new/1" do
    test "creates success result" do
      attrs = %{
        status: :success,
        outputs: %{result: "done"},
        telemetry: %{
          iterations: 1,
          total_tokens: 100,
          total_cost_usd: Decimal.new("0.01"),
          agents_invoked: [:agent_a],
          consensus_score: 1.0
        }
      }

      assert {:ok, %DelegationResult{status: :success}} = DelegationResult.new(attrs)
    end

    test "creates escalation result" do
      attrs = %{
        status: :escalate,
        reason: :no_consensus,
        escalation_request: %{
          type: :human_decision,
          context: "context",
          options: [:approve, :reject],
          agent_positions: %{},
          disagreement_summary: nil
        },
        telemetry: %{
          iterations: 5,
          total_tokens: 100,
          total_cost_usd: Decimal.new("0.01"),
          agents_invoked: [:agent_a],
          consensus_score: 0.3
        }
      }

      assert {:ok, %DelegationResult{status: :escalate}} = DelegationResult.new(attrs)
    end
  end

  describe "serialization" do
    test "JSON roundtrip via Jason" do
      result = %DelegationResult{
        status: :success,
        outputs: %{review: "passed"},
        telemetry: %{
          iterations: 2,
          total_tokens: 5000,
          total_cost_usd: Decimal.new("0.15"),
          agents_invoked: [:reviewer_agent],
          consensus_score: 0.95
        }
      }

      encoded = Jason.encode!(result)
      decoded = Jason.decode!(encoded)

      assert decoded["status"] == "success"
      assert decoded["outputs"]["review"] == "passed"
    end
  end
end
