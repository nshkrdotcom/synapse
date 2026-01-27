defmodule Synapse.RunIndexTestAdapter do
  @moduledoc false

  @behaviour Synapse.RunIndex.Adapter

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{runs: [], steps: []} end, name: __MODULE__)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{runs: [], steps: []} end)
  end

  def data do
    Agent.get(__MODULE__, & &1)
  end

  @impl true
  def write_run(attrs, _opts) do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :runs, &[attrs | &1])
    end)

    :ok
  end

  @impl true
  def write_step(attrs, _opts) do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :steps, &[attrs | &1])
    end)

    :ok
  end
end
