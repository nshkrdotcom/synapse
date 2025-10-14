defmodule SynapseCore.Application do
  @moduledoc """
  The main application supervisor for SynapseCore.
  """
  use Application

  def start(_type, _args) do
    children = [
      # Add supervisors and workers here
      {SynapseCore.PydanticSupervisor, []},
      {GRPC.Server.Supervisor, {SynapseCore.AgentGrpcServer, 50051}}
    ]

    opts = [strategy: :one_for_one, name: SynapseCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
