defmodule Axon.Web.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      {Telemetry.Supervisor, []},
      
      # Start the Endpoint (http/https)
      {Phoenix.PubSub, name: Axon.PubSub},
      {Axon.Web.Endpoint, []}
    ]

    opts = [strategy: :one_for_one, name: Axon.Web.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
