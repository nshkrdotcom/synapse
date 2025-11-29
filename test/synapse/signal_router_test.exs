defmodule Synapse.SignalRouterTest do
  use ExUnit.Case, async: true

  alias Synapse.Signal
  alias Synapse.SignalRouter
  alias Synapse.TestSupport.SignalRouterHelpers, as: RouterHelpers

  describe "dynamic topic support" do
    test "router works with config-defined topics" do
      router = RouterHelpers.start_test_router()

      {:ok, _sub_id} = SignalRouter.subscribe(router, :task_request)

      {:ok, signal} = SignalRouter.publish(router, :task_request, %{task_id: "test-123"})
      assert signal.type == Signal.type(:task_request)

      assert_receive {:signal, received}, 1_000
      assert received.data.task_id == "test-123"
    end

    test "router works with runtime-registered topics" do
      topic = :"custom_topic_#{System.unique_integer([:positive])}"

      :ok =
        Synapse.Signal.register_topic(topic,
          type: "test.custom.#{topic}",
          schema: [id: [type: :string, required: true]]
        )

      router = RouterHelpers.start_test_router()

      {:ok, _sub_id} = SignalRouter.subscribe(router, topic)

      {:ok, _signal} = SignalRouter.publish(router, topic, %{id: "runtime-123"})

      assert_receive {:signal, received}, 1_000
      assert received.data.id == "runtime-123"
    end

    test "subscribing to unregistered topic raises InvalidTopicError" do
      router = RouterHelpers.start_test_router()

      assert_raise SignalRouter.InvalidTopicError, fn ->
        SignalRouter.subscribe(router, :nonexistent_topic)
      end
    end
  end
end
