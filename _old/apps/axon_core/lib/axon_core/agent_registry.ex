defmodule AxonCore.AgentRegistry do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    # Use an ETS table or a Map to store agent information
    {:ok, %{}}
  end

  # Add functions to register, unregister, lookup agents, etc.
end
