defmodule AxonCore.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: AxonFinch}
    ]

    opts = [strategy: :one_for_one, name: AxonCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
