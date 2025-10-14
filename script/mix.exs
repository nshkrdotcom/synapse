defmodule SynapsePython.MixProject do
  use Mix.Project

  def project do
    [
      app: :synapse_python,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:synapse_core, in_umbrella: true},
      # For Python integration
      {:erlport, "~> 0.10.1"},
      # For JSON encoding/decoding
      {:jason, "~> 1.2"}
    ]
  end
end
