defmodule Axon do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      # Axon.Repo, # Comment out for now
      # Start the Telemetry supervisor
      AxonWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Axon.PubSub},
      # Start the Endpoint (http/https)
      AxonWeb.Endpoint,
      # Start a worker by calling: Axon.Worker.start_link(arg)
      # {Axon.Worker, arg}
      # {Axon.Agent, python_module: "location_agent", model: "openai:gpt-4o", name: "python_agent_1"},
      # {Axon.Agent, python_module: "example_agent", model: "openai:gpt-4o", name: "python_agent_2"}
      # {Axon.Agent,
      #   python_module: "agents.example_agent",
      #   model: "openai:gpt-4o",
      #   name: "example_agent"},
      # {Axon.Agent,
      #  python_module: "agents.bank_support_agent",
      #  model: "openai:gpt-4o",
      #  name: "bank_support_agent"}
      supervisor(Axon.Agent, [[
        name: "python_agent_1",
        python_module: "agents.example_agent",
        model: "openai:gpt-4o",
        port: 5001,
        extra_env: [{"PYTHONPATH", "./apps/axon_python/src"}]
      ]]),
      supervisor(Axon.Agent, [[
        name: "python_agent_2",
        python_module: "agents.bank_support_agent",
        model: "openai:gpt-4o",
        port: 5002,
        extra_env: [{"PYTHONPATH", "./apps/axon_python/src"}]
      ]]),

    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Axon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AxonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
