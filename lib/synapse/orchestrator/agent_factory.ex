defmodule Synapse.Orchestrator.AgentFactory do
  @moduledoc """
  Lightweight factory responsible for turning validated `%AgentConfig{}`
  definitions into running processes.

  Dynamic agents subscribe to the router topics defined in their configuration
  and execute the configured actions when signals are received.
  """

  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Orchestrator.DynamicAgent
  alias Synapse.SignalRouter

  @spec spawn(AgentConfig.t(), atom() | nil, atom() | nil) ::
          {:ok, pid()} | {:error, term()}
  def spawn(%AgentConfig{} = config, router, _registry) do
    DynamicAgent.start_link(config: config, router: router || SignalRouter)
  end

  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end
end
