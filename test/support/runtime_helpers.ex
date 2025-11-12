defmodule Synapse.TestSupport.RuntimeHelpers do
  @moduledoc false

  import ExUnit.Callbacks
  alias Synapse.SignalRouter
  alias Synapse.TestSupport.SignalRouterHelpers

  def setup_runtime(context, opts \\ []) do
    runtime_name = Keyword.get(opts, :name, :"runtime_#{System.unique_integer([:positive])}")

    runtime_opts =
      opts
      |> Keyword.put(:name, runtime_name)

    {:ok, _pid} = start_supervised({Synapse.Runtime, runtime_opts})
    runtime = Synapse.Runtime.fetch(runtime_name)

    subscriptions =
      opts
      |> Keyword.get(:subscribe, [])
      |> Enum.map(&SignalRouterHelpers.subscribe_test_process(runtime.router, &1))

    on_exit(fn ->
      Enum.each(subscriptions, fn sub_id ->
        maybe_unsubscribe(runtime.router, sub_id)
      end)
    end)

    context
    |> Map.put(:runtime, runtime)
    |> Map.put(:router, runtime.router)
    |> Map.put(:bus, runtime.bus)
    |> Map.put(:registry, runtime.registry)
    |> Map.put(:signal_router_subscriptions, subscriptions)
    |> then(&{:ok, &1})
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
end
