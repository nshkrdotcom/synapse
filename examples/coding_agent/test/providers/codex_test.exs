defmodule CodingAgent.Providers.CodexTest do
  use ExUnit.Case, async: true

  alias CodingAgent.Providers.Codex
  alias CodingAgent.Task

  describe "name/0" do
    test "returns :codex" do
      assert Codex.name() == :codex
    end
  end

  describe "available?/0" do
    test "returns true when OPENAI_API_KEY is set" do
      if System.get_env("OPENAI_API_KEY") do
        assert Codex.available?() == true
      else
        assert Codex.available?() == false
      end
    end
  end

  describe "execute/2 integration" do
    # Integration tests require actual API key
    @describetag :integration
    @describetag :codex
    test "executes a simple generation task" do
      if Codex.available?() do
        task = Task.new("Say exactly: Hello from Codex", type: :generate)

        assert {:ok, result} = Codex.execute(task)
        assert result.provider == :codex
        assert is_binary(result.content)
      end
    end
  end
end
