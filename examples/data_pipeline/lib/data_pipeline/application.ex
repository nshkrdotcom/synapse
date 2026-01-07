defmodule DataPipeline.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add supervised processes here if needed
      # e.g., a registry for tracking pipeline runs
    ]

    opts = [strategy: :one_for_one, name: DataPipeline.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
