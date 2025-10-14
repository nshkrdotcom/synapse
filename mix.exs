defmodule SynapseCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :synapse_core,
      version: "0.1.0",
      elixir: "~> 1.17",
      build_embedded: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Elixir-Powered AI Agent Orchestration",
      package: package(),
      maintainers: ["nshkrdotcom"]
    ]
  end

  def application do
    [
      mod: {SynapseCore.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:protobuf, "~> 0.13.0"},
      {:grpc, "~> 0.9.0"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:finch, "~> 0.16"}
    ]
  end

  defp aliases do
    []
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/synapse"
      }
    ]
  end
end
