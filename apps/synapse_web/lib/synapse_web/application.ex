defmodule SynapseWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SynapseWeb.Telemetry,
      # Start a worker by calling: SynapseWeb.Worker.start_link(arg)
      # {SynapseWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      SynapseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SynapseWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SynapseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
