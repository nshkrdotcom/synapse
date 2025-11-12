defmodule Synapse.Runtime do
  @moduledoc """
  Supervises the core Synapse runtime components (Signal Router, Agent Registry,
  Specialist Supervisor) and exposes a handle that other modules can use to
  obtain the correct router/bus/registry names without relying on globals.
  """

  use Supervisor

  defstruct [:name, :router, :bus, :registry, :specialist_supervisor]

  @type t :: %__MODULE__{
          name: atom(),
          router: atom(),
          bus: atom(),
          registry: atom(),
          specialist_supervisor: atom()
        }

  @default_name __MODULE__

  @doc """
  Starts a runtime supervisor.

  Options:
    * `:name` - runtime identifier (defaults to #{inspect(@default_name)})
    * `:router_name` - override generated router process name
    * `:bus_name` - override generated bus process name
    * `:registry_name` - override agent registry name
    * `:specialists_name` - override specialist supervisor name
    * `:router_opts` - additional options for `Synapse.SignalRouter.start_link/1`
    * `:bus_opts` - additional options passed through to the router's bus
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    Supervisor.start_link(__MODULE__, {name, opts}, name: name)
  end

  @impl true
  def init({name, opts}) do
    runtime = build_runtime(name, opts)
    :persistent_term.put(runtime_key(name), runtime)

    router_opts =
      opts
      |> Keyword.get(:router_opts, [])
      |> Keyword.merge(
        name: runtime.router,
        bus_name: runtime.bus,
        registry: runtime.registry,
        bus_opts: Keyword.get(opts, :bus_opts, [])
      )

    children = [
      {Synapse.SignalRouter, router_opts},
      {Synapse.AgentRegistry, [name: runtime.registry]},
      {Synapse.SpecialistSupervisor, [name: runtime.specialist_supervisor]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Fetches the runtime handle for the given name (defaults to the application runtime).
  """
  @spec fetch(atom()) :: t()
  def fetch(name \\ @default_name) do
    case :persistent_term.get(runtime_key(name), :not_found) do
      :not_found ->
        raise "Synapse runtime #{inspect(name)} has not been started"

      runtime ->
        runtime
    end
  end

  defp build_runtime(name, opts) do
    runtime_id = Keyword.get(opts, :runtime_id, System.unique_integer([:positive]))
    router_name = Keyword.get(opts, :router_name, :"#{name}_router_#{runtime_id}")
    bus_name = Keyword.get(opts, :bus_name, :"#{name}_bus_#{runtime_id}")
    registry_name = Keyword.get(opts, :registry_name, :"#{name}_registry_#{runtime_id}")
    specialists_name = Keyword.get(opts, :specialists_name, :"#{name}_specialists_#{runtime_id}")

    %__MODULE__{
      name: name,
      router: router_name,
      bus: bus_name,
      registry: registry_name,
      specialist_supervisor: specialists_name
    }
  end

  defp runtime_key(name), do: {__MODULE__, name}
end
