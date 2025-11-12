defmodule Synapse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Synapse.Telemetry.attach_orchestrator_summary_handler()
    runtime_opts = Application.get_env(:synapse, Synapse.Runtime, [])
    runtime_name = Keyword.get(runtime_opts, :name, Synapse.Runtime)
    orchestrator_config = Application.get_env(:synapse, Synapse.Orchestrator.Runtime, [])

    children =
      [
        Synapse.Repo,
        {Synapse.Runtime, runtime_opts}
      ] ++
        orchestrator_children(orchestrator_config, runtime_name) ++
        [
          {DNSCluster, query: Application.get_env(:synapse, :dns_cluster_query) || :ignore}
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Synapse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(_changed, _new, _removed), do: :ok

  defp orchestrator_children(config, runtime_name) do
    case Synapse.Application.Orchestrator.child_spec(config, runtime_name) do
      nil -> []
      spec -> [spec]
    end
  end
end
