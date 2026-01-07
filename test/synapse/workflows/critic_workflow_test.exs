defmodule Synapse.Workflows.CriticWorkflowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox
  alias Synapse.Workflows.CriticWorkflow

  setup do
    :ok = SQLSandbox.checkout(Synapse.Repo)
    :ok
  end

  describe "evaluate/1" do
    test "auto-approves high-confidence reviews" do
      {:ok, result} =
        CriticWorkflow.evaluate(%{
          code: "def foo, do: :ok",
          intent: "Return :ok",
          constraints: []
        })

      assert result.decision.decision == :auto_approve
      refute result.escalate?
      assert result.review.confidence >= 0.7
      assert result.audit_trail.workflow == :critic_workflow
    end

    test "escalates when confidence under custom threshold" do
      {:ok, result} =
        CriticWorkflow.evaluate(%{
          code: "TODO",
          intent: "Placeholder",
          escalation_threshold: 0.85
        })

      assert result.decision.decision == :escalate
      assert result.escalate?
      assert result.decision.reason =~ "Confidence"
    end

    test "invalid inputs return validation error" do
      assert {:error, error} = CriticWorkflow.evaluate(%{})
      assert is_exception(error)
    end
  end
end
