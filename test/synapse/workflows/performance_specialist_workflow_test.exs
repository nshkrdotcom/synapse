defmodule Synapse.Workflows.PerformanceSpecialistWorkflowTest do
  use Synapse.SupertesterCase, async: false

  alias Synapse.Workflows.PerformanceSpecialistWorkflow

  test "detects high complexity in diff" do
    diff = """
    +def complicated(x) do
    +  if x > 0 do
    +    cond do
    +      x == 1 -> :one
    +      x == 2 -> :two
    +      true -> case x do
    +        3 -> :three
    +        4 -> :four
    +        _ -> :many
    +      end
    +    end
    +  else
    +    :none
    +  end
    +end
    """

    {:ok, %{results: results}} =
      PerformanceSpecialistWorkflow.evaluate(%{
        diff: diff,
        files: ["lib/perf.ex"],
        metadata: %{},
        language: "elixir"
      })

    assert Enum.count(results) == 3

    assert Enum.any?(results, fn result ->
             Enum.any?(result.findings, &(&1.type == :high_complexity))
           end)
  end
end
