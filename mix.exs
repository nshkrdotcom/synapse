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
      # build_path: "_build",
      deps: deps(),
      aliases: aliases()
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
      # Umbrella apps
      # {:synapse_core, path: "apps/synapse_core"},
      # {:synapse_python, path: "apps/synapse_python"},

      # Direct dependencies
      # {:phoenix, "~> 1.7.0"},
      # {:phoenix_html, "~> 3.3"},
      # {:phoenix_live_reload, "~> 1.4", only: :dev},
      # {:phoenix_live_view, "~> 0.19.0"},
      # {:floki, ">= 0.30.0", only: :test},
      # {:phoenix_live_dashboard, "~> 0.8.0"},
      # {:telemetry_metrics, "~> 0.6"},
      # {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:protobuf, "~> 0.13.0"},
      {:grpc, "~> 0.9.0"},
      # {:google_protos, "~> 0.3.0"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:finch, "~> 0.16"}
      # {:plug_cowboy, "~> 2.5"},
    ]
  end

  defp aliases do
    [
      # setup: ["deps.get", "cmd --app synapse_python mix setup"],
      # test: ["test"],
      # "assets.deploy": []
    ]
  end
end

# defmodule SynapseCore.MixProject do
#   use Mix.Project

#   def project do
#     [
#       app: :synapse_core,
#       version: "0.1.0",
#       build_path: "../../_build",
#       config_path: "../../config/config.exs",
#       deps_path: "../../deps",
#       lockfile: "../../mix.lock",
#       elixir: "~> 1.14",
#       elixirc_paths: elixirc_paths(Mix.env()),
#       start_permanent: Mix.env() == :prod,
#       deps: deps()
#     ]
#   end

#   defp elixirc_paths(:test), do: ["lib", "test"]
#   defp elixirc_paths(_), do: ["lib"]

#   def application do
#     [
#       extra_applications: [:logger, :finch],
#       mod: {SynapseCore.Application, []}
#     ]
#   end

#   defp deps do
#     [
#       #{:grpc, "~> 0.9.0"},
#       #{:protobuf, "~> 0.13.0"},
#       # {:google_protos, "~> 0.3.0"},
#       {:jason, "~> 1.4"},
#       {:tesla, "~> 1.7"},
#       {:hackney, "~> 1.18"},
#       {:finch, "~> 0.16"},

#       #{:exile, "~> 0.12.0"},
#     ]
#   end
# end
