defmodule ResearchAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :research_agent,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {ResearchAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parent framework
      {:synapse, path: "../.."},

      # AI providers
      {:claude_agent_sdk, "~> 0.6.4"},
      {:gemini_ex, "~> 0.7.2"},

      # HTTP client for web search/fetch
      {:req, "~> 0.5"},

      # Testing
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end
end
