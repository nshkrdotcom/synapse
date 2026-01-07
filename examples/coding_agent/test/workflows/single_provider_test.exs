defmodule CodingAgent.Workflows.SingleProviderTest do
  use ExUnit.Case

  alias CodingAgent.{Task, Workflows.SingleProvider}

  # Integration tests require API keys
  @tag :integration
  describe "run/2 integration" do
    test "executes task with gemini provider" do
      if CodingAgent.provider_available?(:gemini) do
        task = Task.new("Say: Hello from workflow", type: :generate)

        assert {:ok, result} = SingleProvider.run(task, :gemini)
        assert result.result.content =~ "Hello"
      end
    end
  end
end
