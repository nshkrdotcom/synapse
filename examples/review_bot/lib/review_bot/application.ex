defmodule ReviewBot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ReviewBot.Repo,
      {DNSCluster, query: Application.get_env(:review_bot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ReviewBot.PubSub},
      ReviewBotWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ReviewBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ReviewBotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
