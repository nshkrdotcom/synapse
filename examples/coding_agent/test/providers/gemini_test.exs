defmodule CodingAgent.Providers.GeminiTest do
  use ExUnit.Case, async: true

  alias CodingAgent.Providers.Gemini
  alias CodingAgent.Task

  describe "name/0" do
    test "returns :gemini" do
      assert Gemini.name() == :gemini
    end
  end

  describe "available?/0" do
    test "returns true when GEMINI_API_KEY is set" do
      if System.get_env("GEMINI_API_KEY") do
        assert Gemini.available?() == true
      else
        assert Gemini.available?() == false
      end
    end
  end

  describe "execute/2 integration" do
    # Integration tests require actual API key
    @describetag :integration
    @describetag :gemini
    test "executes a simple generation task" do
      if Gemini.available?() do
        task = Task.new("Say exactly: Hello from Gemini", type: :generate)

        assert {:ok, result} = Gemini.execute(task)
        assert result.provider == :gemini
        assert is_binary(result.content)
        assert result.content =~ "Hello"
      end
    end
  end
end
