defmodule DocGenerator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add any supervised processes here in the future
      # e.g., telemetry handlers, caches, etc.
    ]

    opts = [strategy: :one_for_one, name: DocGenerator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
