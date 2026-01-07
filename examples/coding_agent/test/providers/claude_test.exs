defmodule CodingAgent.Providers.ClaudeTest do
  use ExUnit.Case, async: true

  alias CodingAgent.Providers.Claude
  alias CodingAgent.Task

  describe "name/0" do
    test "returns :claude" do
      assert Claude.name() == :claude
    end
  end

  describe "available?/0" do
    test "returns true when ANTHROPIC_API_KEY is set" do
      # This test depends on environment - skip in CI without key
      if System.get_env("ANTHROPIC_API_KEY") do
        assert Claude.available?() == true
      else
        assert Claude.available?() == false
      end
    end
  end

  describe "execute/2 integration" do
    # Integration tests require actual API key
    @describetag :integration
    @describetag :claude
    test "executes a simple generation task" do
      if Claude.available?() do
        task = Task.new("Say exactly: Hello from Claude", type: :generate)

        assert {:ok, result} = Claude.execute(task)
        assert result.provider == :claude
        assert is_binary(result.content)
        assert result.content =~ "Hello"
      end
    end
  end
end
