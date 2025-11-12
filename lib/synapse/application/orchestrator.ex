defmodule Synapse.Application.Orchestrator do
  @moduledoc false

  alias Synapse.Orchestrator.Runtime

  @default_config_source {:priv, "orchestrator_agents.exs"}

  @doc """
  Builds a child spec for the declarative orchestrator runtime when enabled.
  """
  @spec child_spec(keyword(), atom()) :: Supervisor.child_spec() | nil
  def child_spec(config, runtime_name) do
    config = config || []

    if Keyword.get(config, :enabled, false) do
      opts =
        config
        |> Keyword.delete(:enabled)
        |> Keyword.put(:runtime_name, runtime_name)

      %{
        id: Keyword.get(opts, :name, Runtime),
        start: {__MODULE__, :start_link, [opts]},
        type: :supervisor
      }
    else
      nil
    end
  end

  @doc false
  def start_link(opts) do
    runtime_name = Keyword.get(opts, :runtime_name, Synapse.Runtime)
    runtime = Synapse.Runtime.fetch(runtime_name)

    orchestrator_opts =
      opts
      |> Keyword.delete(:runtime_name)
      |> Keyword.put_new(:router, runtime.router)
      |> Keyword.put_new(:registry, runtime.registry)
      |> ensure_config_source()

    Runtime.start_link(orchestrator_opts)
  end

  defp ensure_config_source(opts) do
    source = Keyword.get(opts, :config_source, @default_config_source)
    Keyword.put(opts, :config_source, resolve_config_source(source))
  end

  defp resolve_config_source({:priv, relative}) do
    :synapse
    |> :code.priv_dir()
    |> to_string()
    |> Path.join(relative)
  end

  defp resolve_config_source({:app, app, relative}) do
    app
    |> Application.app_dir()
    |> Path.join(relative)
  end

  defp resolve_config_source(path) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, File.cwd!())
    end
  end
end
