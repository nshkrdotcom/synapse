defmodule CodingAgent.Test.Fixtures do
  @moduledoc """
  Test fixtures for coding agent tests.
  """

  alias CodingAgent.Task

  def sample_task(overrides \\ []) do
    defaults = [
      input: "Write a function to parse JSON",
      type: :generate,
      context: nil,
      language: "elixir"
    ]

    opts = Keyword.merge(defaults, overrides)
    Task.new(opts[:input], opts)
  end

  def sample_result(provider, overrides \\ []) do
    defaults = %{
      content:
        "Here is the generated code:\n\n```elixir\ndef parse_json(input), do: Jason.decode!(input)\n```",
      provider: provider,
      model: model_for(provider),
      usage: %{input_tokens: 100, output_tokens: 50},
      raw: %{}
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp model_for(:claude), do: "claude-3-5-sonnet-20241022"
  defp model_for(:codex), do: "o4-mini"
  defp model_for(:gemini), do: "gemini-2.0-flash-exp"
end
