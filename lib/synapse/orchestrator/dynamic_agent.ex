defmodule Synapse.Orchestrator.DynamicAgent do
  @moduledoc """
  Router-native runtime worker that executes declaratively configured agents.

  Each dynamic agent subscribes to the configured `Synapse.SignalRouter` topics,
  runs the configured Jido actions, and emits results back through the router.
  """

  use GenServer

  require Logger

  alias Jido.Exec
  alias Synapse.Orchestrator.Actions.RunConfig
  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.SignalRouter

  @type option ::
          {:config, AgentConfig.t()}
          | {:router, atom()}

  ## Client API

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    router = Keyword.fetch!(opts, :router)

    Process.flag(:trap_exit, true)

    subscriptions =
      Enum.map(config.signals.subscribes, fn topic ->
        {:ok, sub_id} = SignalRouter.subscribe(router, topic, target: self())
        {topic, sub_id}
      end)

    state = %{
      config: config,
      router: router,
      subscriptions: subscriptions,
      agent_state: build_initial_state(config.state_schema)
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    case process_signal(signal, state) do
      {:ok, new_agent_state} ->
        {:noreply, %{state | agent_state: new_agent_state}}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.subscriptions, fn {_topic, sub_id} ->
      maybe_unsubscribe(state.router, sub_id)
    end)

    :ok
  end

  ## Internal helpers

  defp process_signal(signal, state) do
    request_id =
      signal.data
      |> Map.new()
      |> then(fn data ->
        Map.get(data, :request_id) ||
          Map.get(data, "request_id") ||
          Map.get(data, :review_id) ||
          Map.get(data, "review_id")
      end)

    params =
      signal.data
      |> Map.new()
      |> maybe_put_request_id(request_id)
      |> Map.put(:_config, state.config)
      |> Map.put(:_router, state.router)
      |> Map.put(:_emits, state.config.signals.emits || [])
      |> Map.put(:_signal, signal)
      |> Map.put(:_state, state.agent_state)

    case Exec.run(RunConfig, params, %{}) do
      {:ok, run_result} ->
        {:ok, extract_agent_state(run_result, state.agent_state)}

      {:error, reason} ->
        Logger.warning("Dynamic agent failed to execute config",
          agent_id: state.config.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp maybe_unsubscribe(router, sub_id) do
    if Process.whereis(router) do
      try do
        SignalRouter.unsubscribe(router, sub_id)
      catch
        :exit, _ -> :ok
      end
    else
      :ok
    end
  end

  defp maybe_put_request_id(map, nil), do: map
  defp maybe_put_request_id(map, request_id), do: Map.put_new(map, :request_id, request_id)

  defp build_initial_state(nil), do: %{}

  defp build_initial_state(schema) when is_list(schema) do
    Enum.reduce(schema, %{}, fn
      {key, opts}, acc when is_atom(key) and is_list(opts) ->
        Map.put(acc, key, Keyword.get(opts, :default))

      _, acc ->
        acc
    end)
  end

  defp build_initial_state(_), do: %{}

  defp extract_agent_state(%{state: new_state}, _current) when is_map(new_state), do: new_state
  defp extract_agent_state(_, current), do: current
end
