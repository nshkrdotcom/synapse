defmodule Synapse.Signal.RegistryTest do
  use ExUnit.Case, async: false

  alias Synapse.Signal.Registry

  setup do
    name = :"test_registry_#{:rand.uniform(100_000)}"
    {:ok, pid} = Registry.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{registry: name}
  end

  describe "start_link/1" do
    test "starts the registry process" do
      assert {:ok, pid} = Registry.start_link(name: :test_start)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "loads topics from config on startup" do
      previous = Application.get_env(:synapse, Synapse.Signal.Registry, [])

      Application.put_env(:synapse, Synapse.Signal.Registry,
        topics: [
          configured_topic: [
            type: "configured.topic",
            schema: [id: [type: :string, required: true]]
          ]
        ]
      )

      on_exit(fn ->
        Application.put_env(:synapse, Synapse.Signal.Registry, previous)
      end)

      name = :"registry_config_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Registry.start_link(name: name)

      assert {:ok, %{type: "configured.topic"}} = Registry.get_topic(name, :configured_topic)
    end

    test "auto-registers configured domains" do
      previous_domains = Application.get_env(:synapse, :domains, [])
      Application.put_env(:synapse, :domains, [Synapse.Domains.CodeReview])

      name = :"registry_domain_#{System.unique_integer([:positive])}"
      {:ok, pid} = Registry.start_link(name: name)

      on_exit(fn ->
        Application.put_env(:synapse, :domains, previous_domains)

        if Process.alive?(pid) do
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      assert {:ok, %{type: "review.request"}} = Registry.get_topic(name, :review_request)
    end
  end

  describe "register_topic/2" do
    test "registers a new topic with inline schema", %{registry: registry} do
      assert :ok =
               Registry.register_topic(registry, :my_topic,
                 type: "my.topic",
                 schema: [
                   id: [type: :string, required: true],
                   data: [type: :map, default: %{}]
                 ]
               )

      assert {:ok, config} = Registry.get_topic(registry, :my_topic)
      assert config.type == "my.topic"
    end

    test "rejects duplicate topic registration", %{registry: registry} do
      Registry.register_topic(registry, :dupe, type: "dupe", schema: [])

      assert {:error, :already_registered} =
               Registry.register_topic(registry, :dupe, type: "dupe", schema: [])
    end

    test "validates topic config structure", %{registry: registry} do
      assert {:error, _} = Registry.register_topic(registry, :bad, type: 123, schema: [])
      assert {:error, _} = Registry.register_topic(registry, :bad, schema: [])
    end
  end

  describe "get_topic/2" do
    test "returns topic config for registered topic", %{registry: registry} do
      Registry.register_topic(registry, :task,
        type: "task.request",
        schema: [id: [type: :string, required: true]]
      )

      assert {:ok, %{type: "task.request"}} = Registry.get_topic(registry, :task)
    end

    test "returns error for unknown topic", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_topic(registry, :unknown)
    end
  end

  describe "list_topics/1" do
    test "returns all registered topics", %{registry: registry} do
      Registry.register_topic(registry, :a, type: "a", schema: [])
      Registry.register_topic(registry, :b, type: "b", schema: [])

      topics = Registry.list_topics(registry)
      assert :a in topics
      assert :b in topics
    end
  end

  describe "type/2" do
    test "returns wire type for topic", %{registry: registry} do
      Registry.register_topic(registry, :task, type: "synapse.task", schema: [])
      assert "synapse.task" = Registry.type(registry, :task)
    end

    test "raises for unknown topic", %{registry: registry} do
      assert_raise KeyError, fn -> Registry.type(registry, :unknown) end
    end
  end

  describe "topic_from_type/2" do
    test "resolves wire type to topic atom", %{registry: registry} do
      Registry.register_topic(registry, :task, type: "synapse.task", schema: [])
      assert {:ok, :task} = Registry.topic_from_type(registry, "synapse.task")
    end

    test "returns error for unknown type", %{registry: registry} do
      assert :error = Registry.topic_from_type(registry, "unknown.type")
    end
  end

  describe "validate!/3" do
    test "validates payload against topic schema", %{registry: registry} do
      Registry.register_topic(registry, :task,
        type: "task",
        schema: [
          id: [type: :string, required: true],
          priority: [type: {:in, [:low, :high]}, default: :low]
        ]
      )

      result = Registry.validate!(registry, :task, %{id: "123"})
      assert result.id == "123"
      assert result.priority == :low
    end

    test "raises on invalid payload", %{registry: registry} do
      Registry.register_topic(registry, :task,
        type: "task",
        schema: [id: [type: :string, required: true]]
      )

      assert_raise ArgumentError, fn ->
        Registry.validate!(registry, :task, %{})
      end
    end

    test "raises for unknown topic", %{registry: registry} do
      assert_raise KeyError, fn ->
        Registry.validate!(registry, :unknown, %{})
      end
    end
  end

  describe "unregister_topic/2" do
    test "removes a registered topic", %{registry: registry} do
      Registry.register_topic(registry, :temp, type: "temp", schema: [])
      assert :ok = Registry.unregister_topic(registry, :temp)
      assert {:error, :not_found} = Registry.get_topic(registry, :temp)
    end
  end
end
