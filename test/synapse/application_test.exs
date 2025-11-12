defmodule Synapse.ApplicationTest do
  use ExUnit.Case, async: false

  import ExUnit.Callbacks

  setup_all do
    runtime =
      case fetch_default_runtime() do
        {:ok, rt} ->
          rt

        :error ->
          name = :"test_app_runtime_#{System.unique_integer([:positive])}"
          {:ok, _pid} = start_supervised({Synapse.Runtime, name: name})
          Synapse.Runtime.fetch(name)
      end

    {:ok, %{runtime: runtime}}
  end

  describe "Application supervision tree" do
    test "starts SignalRouter", %{runtime: runtime} do
      assert Process.whereis(runtime.router)

      info = Synapse.SignalRouter.fetch(runtime.router)
      assert info.bus == runtime.bus
    end

    test "SignalRouter accepts subscriptions", %{runtime: runtime} do
      {:ok, sub_id} = Synapse.SignalRouter.subscribe(runtime.router, :review_summary)

      :ok = Synapse.SignalRouter.unsubscribe(runtime.router, sub_id)
    end

    test "SignalRouter delivers published signals", %{runtime: runtime} do
      {:ok, sub_id} = Synapse.SignalRouter.subscribe(runtime.router, :review_summary)

      {:ok, signal} =
        Synapse.SignalRouter.publish(runtime.router, :review_summary, %{
          review_id: "router_test",
          findings: [],
          metadata: %{decision_path: :fast_path}
        })

      assert_receive {:signal, ^signal}, 1_000
      :ok = Synapse.SignalRouter.unsubscribe(runtime.router, sub_id)
    end

    test "starts AgentRegistry", %{runtime: runtime} do
      assert Process.whereis(runtime.registry)
    end
  end

  defp fetch_default_runtime do
    {:ok, Synapse.Runtime.fetch()}
  rescue
    _ -> :error
  end
end
