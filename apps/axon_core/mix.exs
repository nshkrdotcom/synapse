defmodule AxonCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :axon_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_options: [
        exclude: [
          ~r/lib\/axon_core\/agent_process\.ex/,
          ~r/lib\/axon_core\/tool_utils\.ex/,
        ],
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AxonCore.Application, []}
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.7.0"},
      {:protobuf, "~> 0.11.0"},
      {:google_protos, "~> 0.3.0"},
      {:jason, "~> 1.4"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"}
    ]
  end
end
