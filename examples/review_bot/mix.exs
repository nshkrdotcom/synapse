defmodule ReviewBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :review_bot,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ReviewBot.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Synapse framework
      {:synapse, path: "../.."},

      # Phoenix
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 0.20.17"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_ecto, "~> 4.6"},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},

      # Web server
      {:bandit, "~> 1.5"},

      # JSON
      {:jason, "~> 1.2"},

      # AI Provider SDKs (optional)
      {:req, "~> 0.5"},

      # Testing
      {:mox, "~> 1.1", only: :test},
      {:floki, "~> 0.36", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["cmd --cd assets npm install"]
    ]
  end
end
