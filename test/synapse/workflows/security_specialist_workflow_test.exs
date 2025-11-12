defmodule Synapse.Workflows.SecuritySpecialistWorkflowTest do
  use Synapse.SupertesterCase, async: false

  alias Synapse.Workflows.SecuritySpecialistWorkflow

  test "runs all security checks and aggregates results" do
    diff = """
    +query = "SELECT * FROM users WHERE id = '\#{user_input}'"
    """

    {:ok, %{results: results}} =
      SecuritySpecialistWorkflow.evaluate(%{
        diff: diff,
        files: ["lib/app.ex"],
        metadata: %{}
      })

    assert length(results) == 3

    assert Enum.any?(results, fn result ->
             Enum.any?(result.findings, &(&1.type == :sql_injection))
           end)
  end
end
