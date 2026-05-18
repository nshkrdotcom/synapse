defmodule Synapse.MixProject do
  use Mix.Project

  def project do
    [
      app: :synapse_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Synapse.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:app_kit_core, path: "../../../app_kit/core/app_kit_core"},
      {:app_kit_budget_surface, path: "../../../app_kit/core/budget_surface"},
      {:app_kit_context_budget_surface, path: "../../../app_kit/core/context_budget_surface"},
      {:app_kit_coordination_surface, path: "../../../app_kit/core/coordination_surface"},
      {:app_kit_cost_surface, path: "../../../app_kit/core/cost_surface"},
      {:app_kit_hive_surface, path: "../../../app_kit/core/hive_surface"},
      {:app_kit_memory_surface, path: "../../../app_kit/core/memory_surface"},
      {:app_kit_model_surface, path: "../../../app_kit/core/model_surface"},
      {:app_kit_skill_surface, path: "../../../app_kit/core/skill_surface"},
      {:dns_cluster, "~> 0.2.0"},
      {:mezzanine_pack_model, path: "../../../mezzanine/core/pack_model"},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
