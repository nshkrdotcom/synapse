defmodule Synapse.SpecialistSupervisor do
  @moduledoc """
  Dynamic supervisor responsible for running specialist agent servers (security, performance, etc.).

  Every specialist started through this module inherits the lifecycle of the top-level Synapse supervision tree,
  ensuring coordinator restarts do not crash long-lived specialist processes.
  """

  use DynamicSupervisor

  @doc false
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts (or finds) a specialist child under the supervisor.

  Returns `{:ok, pid}` on success, mirroring `DynamicSupervisor.start_child/2`.
  """
  @spec start_specialist(GenServer.server(), module(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_specialist(supervisor \\ __MODULE__, module, opts) do
    case DynamicSupervisor.start_child(supervisor, {module, opts}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
