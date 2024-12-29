defmodule Axon.MixProject do
  use Mix.Project

  def project do
    [
      app: :axon,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Axon.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Umbrella apps
      {:axon_core, path: "apps/axon_core"},
      {:axon_python, path: "apps/axon_python"},

      # Direct dependencies
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.19.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.11"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd --app axon_python mix setup"],
      test: ["test"],
      "assets.deploy": []
    ]
  end
end
