defmodule Synapse.SignalTest do
  use ExUnit.Case, async: false

  alias Synapse.Signal
  alias Synapse.Signal.Registry

  setup_all do
    if is_nil(Process.whereis(Registry)) do
      {:ok, _pid} = Registry.start_link()
    end

    :ok
  end

  describe "type/1" do
    test "returns wire type for registered topic" do
      assert is_binary(Signal.type(:task_request))
    end
  end

  describe "topics/0" do
    test "returns list of all registered topics" do
      topics = Signal.topics()

      assert is_list(topics)
      assert :task_request in topics
    end
  end

  describe "validate!/2" do
    test "validates and returns normalized payload" do
      payload = %{task_id: "123"}
      result = Signal.validate!(:task_request, payload)

      assert result.task_id == "123"
    end
  end

  describe "topic_from_type/1" do
    test "resolves type string to topic" do
      type = Signal.type(:task_request)
      assert {:ok, :task_request} = Signal.topic_from_type(type)
    end
  end

  describe "register_topic/2" do
    test "allows runtime topic registration" do
      topic = :"test_topic_#{:rand.uniform(100_000)}"

      on_exit(fn -> Registry.unregister_topic(topic) end)

      assert :ok =
               Signal.register_topic(topic,
                 type: "test.topic.#{topic}",
                 schema: [id: [type: :string, required: true]]
               )

      assert topic in Signal.topics()
    end
  end
end
