defmodule AxonPython.MixProject do
  use Mix.Project

  def project do
    [
      app: :axon_python,
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
      {:axon_core, in_umbrella: true},
      {:erlport, "~> 0.10.1"},  # For Python integration
      {:jason, "~> 1.2"}        # For JSON encoding/decoding
    ]
  end
end
