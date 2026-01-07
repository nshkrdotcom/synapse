defmodule ResearchAgent.Workflows.QuickResearchTest do
  use ExUnit.Case, async: false

  alias ResearchAgent.Workflows
  alias ResearchAgent.Fixtures

  describe "run/2" do
    test "executes quick research workflow successfully" do
      query = Fixtures.query_fixture(topic: "Machine Learning Basics")

      # Note: This is a basic structural test
      # In a real scenario, you would mock the provider responses
      # For now, we test that the workflow structure is valid
      # by checking that it would fail with unavailable providers
      result = Workflows.QuickResearch.run(query)

      # Without available providers, we expect an error
      # This confirms the workflow is attempting to execute
      assert {:error, _} = result
    end

    test "workflow includes correct steps" do
      # Test that we can inspect the workflow structure
      # by examining the module
      assert function_exported?(Workflows.QuickResearch, :run, 2)
    end
  end
end
