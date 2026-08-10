unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Synapse.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:app_kit_core, @repo_root),
      DependencySources.dep(:app_kit_budget_surface, @repo_root),
      DependencySources.dep(:app_kit_context_budget_surface, @repo_root),
      DependencySources.dep(:app_kit_coordination_surface, @repo_root),
      DependencySources.dep(:app_kit_cost_surface, @repo_root),
      DependencySources.dep(:app_kit_hive_surface, @repo_root),
      DependencySources.dep(:app_kit_memory_surface, @repo_root),
      DependencySources.dep(:app_kit_model_surface, @repo_root),
      DependencySources.dep(:app_kit_operator_surface, @repo_root),
      DependencySources.dep(:app_kit_replay_surface, @repo_root),
      DependencySources.dep(:app_kit_review_surface, @repo_root, runtime: false),
      DependencySources.dep(:app_kit_skill_surface, @repo_root),
      {:dns_cluster, "~> 0.2.0"},
      DependencySources.dep(:mezzanine_pack_model, @repo_root),
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