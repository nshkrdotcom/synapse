defmodule TestWriter.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_writer,
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
      mod: {TestWriter.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Parent framework
      {:synapse, path: "../.."},

      # SDK dependencies
      {:codex_sdk, "~> 0.2.1"},

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
