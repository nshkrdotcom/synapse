defmodule AxonCore.Application do
  @moduledoc """
  The main application supervisor for AxonCore.
  """
  use Application

  def start(_type, _args) do
    children = [
      # Add supervisors and workers here
      {AxonCore.PydanticSupervisor, []},
      {GRPC.Server.Supervisor, {AxonCore.AgentGrpcServer, 50051}}
    ]

    opts = [strategy: :one_for_one, name: AxonCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
