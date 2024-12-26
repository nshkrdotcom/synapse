defmodule Axon do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      Axon.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Axon.PubSub},
      # Start the agents
      {Axon.Agent, 
        name: "python_agent_1",
        python_module: "agents.example_agent",
        model: "openai:gpt-4o",
        port: 5001,
        extra_env: [{"PYTHONPATH", "./apps/axon_python/src"}]
      },
      {Axon.Agent,
        name: "python_agent_2",
        python_module: "agents.bank_support_agent",
        model: "openai:gpt-4o",
        port: 5002,
        extra_env: [{"PYTHONPATH", "./apps/axon_python/src"}]
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Axon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
