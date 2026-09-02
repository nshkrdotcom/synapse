if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Synapse.MixProject do
  use Mix.Project

  def project do
    [
      app: :synapse,
      version: "0.1.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Synapse",
      description: description(),
      source_url: "https://github.com/nshkrdotcom/synapse",
      homepage_url: "https://github.com/nshkrdotcom/synapse",
      docs: docs(),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        ignore_warnings: "dialyzer.ignore-warnings.exs"
      ]
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

  def cli do
    [
      preferred_envs: [precommit: :test]
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
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:jido, "~> 2.0.0-rc.1"},
      {:jido_action, "~> 2.0.0-rc.1"},
      {:jido_signal, "~> 2.0.0-rc.1"},
      {:lineage_ir, "~> 0.1"},
      {:nsai_work, "~> 0.1"},
      {:req, "~> 0.5"},
      {:nimble_options, "~> 1.0"},

      # AI Layer (optional, for altar_ai integration)
      workspace_dep({:altar_ai, "~> 0.1.0", optional: true}),
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:supertester, "~> 0.5.1", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      precommit: [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp description do
    "Declarative, headless multi-agent runtime for code review orchestration with signals, workflows, and Postgres persistence."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/synapse",
        "Changelog" => "https://github.com/nshkrdotcom/synapse/blob/v0.1.1/CHANGELOG.md",
        "License" => "https://github.com/nshkrdotcom/synapse/blob/v0.1.1/LICENSE"
      },
      files: [
        "lib",
        "assets",
        "priv",
        "docs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v0.1.1",
      logo: "assets/synapse.svg",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "docs/guides/custom-domains.md",
        "docs/guides/plan-compiler.md",
        "docs/guides/migration-0.1.1.md"
      ],
      assets: %{"assets" => "assets"}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
