defmodule TestWriter.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add any supervised processes here if needed
      # For example, a cache or registry for generated tests
    ]

    opts = [strategy: :one_for_one, name: TestWriter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
