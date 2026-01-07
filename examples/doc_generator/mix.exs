defmodule DocGenerator.MixProject do
  use Mix.Project

  def project do
    [
      app: :doc_generator,
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
      mod: {DocGenerator.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parent framework
      {:synapse, path: "../.."},

      # SDK dependencies for AI providers
      {:claude_agent_sdk, "~> 0.6.4"},
      {:codex_sdk, "~> 0.2.1"},
      {:gemini_ex, "~> 0.7.2"},

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
