defmodule Synapse.DelegationRequestTest do
  use ExUnit.Case, async: true

  alias Synapse.DelegationRequest

  describe "struct" do
    test "creates valid struct with all required fields" do
      request = %DelegationRequest{
        run_id: "run-123",
        step_id: "review-code-changes",
        synapse_spec: %{
          coordinator: :code_review_coordinator,
          agents: [:reviewer_agent, :security_agent],
          max_iterations: 5,
          consensus_threshold: 0.8,
          escalation_policy: :always_escalate
        },
        inputs: %{code_diff: "diff content", requirements: ["req1"]},
        context: %{
          agent_runner: MockAgentRunner,
          artifact_store: MockArtifactStore,
          approval_gate: MockApprovalGate,
          git: MockGit,
          progress: MockProgress,
          timeout_remaining_ms: 280_000
        },
        timeout_ms: 300_000
      }

      assert request.run_id == "run-123"
      assert request.step_id == "review-code-changes"
      assert request.synapse_spec.coordinator == :code_review_coordinator
      assert request.synapse_spec.agents == [:reviewer_agent, :security_agent]
      assert request.synapse_spec.max_iterations == 5
      assert request.synapse_spec.consensus_threshold == 0.8
      assert request.synapse_spec.escalation_policy == :always_escalate
      assert request.inputs.code_diff == "diff content"
      assert request.context.agent_runner == MockAgentRunner
      assert request.context.timeout_remaining_ms == 280_000
      assert request.timeout_ms == 300_000
    end

    test "default values for optional fields" do
      request = %DelegationRequest{}

      assert request.run_id == nil
      assert request.step_id == nil
      assert request.synapse_spec == nil
      assert request.inputs == nil
      assert request.context == nil
      assert request.timeout_ms == nil
    end
  end

  describe "validate/1" do
    test "passes for valid input" do
      attrs = valid_attrs()
      assert {:ok, _request} = DelegationRequest.validate(attrs)
    end

    test "fails for missing required field run_id" do
      attrs = valid_attrs() |> Map.delete(:run_id)
      assert {:error, _reason} = DelegationRequest.validate(attrs)
    end

    test "fails for missing required field step_id" do
      attrs = valid_attrs() |> Map.delete(:step_id)
      assert {:error, _reason} = DelegationRequest.validate(attrs)
    end

    test "fails for missing required field synapse_spec" do
      attrs = valid_attrs() |> Map.delete(:synapse_spec)
      assert {:error, _reason} = DelegationRequest.validate(attrs)
    end

    test "fails for invalid synapse_spec missing agents" do
      attrs = valid_attrs() |> put_in([:synapse_spec, :agents], [])
      assert {:error, _reason} = DelegationRequest.validate(attrs)
    end

    test "fails for invalid escalation_policy" do
      attrs = valid_attrs() |> put_in([:synapse_spec, :escalation_policy], :invalid_policy)
      assert {:error, _reason} = DelegationRequest.validate(attrs)
    end

    test "accepts canonical escalation policies" do
      for policy <- [:always_escalate, :on_failure, :on_no_consensus, :never_escalate] do
        attrs = valid_attrs() |> put_in([:synapse_spec, :escalation_policy], policy)
        assert {:ok, _request} = DelegationRequest.validate(attrs)
      end
    end

    test "accepts :human_approval as alias for :always_escalate" do
      attrs = valid_attrs() |> put_in([:synapse_spec, :escalation_policy], :human_approval)
      assert {:ok, request} = DelegationRequest.validate(attrs)
      assert request.synapse_spec.escalation_policy == :always_escalate
    end
  end

  describe "new/1" do
    test "creates struct from valid attrs" do
      attrs = valid_attrs()
      assert {:ok, %DelegationRequest{} = request} = DelegationRequest.new(attrs)
      assert request.run_id == "run-123"
    end

    test "returns error for invalid attrs" do
      assert {:error, _reason} = DelegationRequest.new(%{})
    end
  end

  describe "serialization" do
    test "JSON roundtrip via Jason" do
      request = %DelegationRequest{
        run_id: "run-123",
        step_id: "step-1",
        synapse_spec: %{
          coordinator: :code_review_coordinator,
          agents: [:reviewer_agent],
          max_iterations: 3,
          consensus_threshold: 0.8,
          escalation_policy: :on_failure
        },
        inputs: %{data: "test"},
        context: %{timeout_remaining_ms: 100_000},
        timeout_ms: 120_000
      }

      encoded = Jason.encode!(request)
      decoded = Jason.decode!(encoded)

      assert decoded["run_id"] == "run-123"
      assert decoded["step_id"] == "step-1"
      assert decoded["timeout_ms"] == 120_000
    end
  end

  defp valid_attrs do
    %{
      run_id: "run-123",
      step_id: "review-code-changes",
      synapse_spec: %{
        coordinator: :code_review_coordinator,
        agents: [:reviewer_agent, :security_agent],
        max_iterations: 5,
        consensus_threshold: 0.8,
        escalation_policy: :always_escalate
      },
      inputs: %{code_diff: "diff content"},
      context: %{
        agent_runner: MockAgentRunner,
        artifact_store: MockArtifactStore,
        approval_gate: MockApprovalGate,
        git: MockGit,
        progress: MockProgress,
        timeout_remaining_ms: 280_000
      },
      timeout_ms: 300_000
    }
  end
end
