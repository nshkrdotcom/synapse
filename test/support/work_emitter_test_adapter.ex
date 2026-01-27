defmodule Synapse.WorkEmitterTestAdapter do
  @moduledoc false

  @behaviour Synapse.WorkEmitter.Adapter

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{events: []} end, name: __MODULE__)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{events: []} end)
  end

  def data do
    Agent.get(__MODULE__, & &1)
  end

  @impl true
  def emit(event, job, _opts) do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :events, &[{event, job} | &1])
    end)

    :ok
  end
end
