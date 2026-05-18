defmodule Synapse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DNSCluster, query: Application.get_env(:synapse_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Synapse.PubSub}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Synapse.Supervisor)
  end
end
