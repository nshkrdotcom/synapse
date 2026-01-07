defmodule DataPipeline.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_pipeline,
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
      mod: {DataPipeline.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parent framework
      {:synapse, path: "../.."},

      # AI providers
      {:gemini_ex, "~> 0.7.2"},

      # Utilities
      {:jason, "~> 1.4"},

      # Testing
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    []
  end
end
