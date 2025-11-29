defmodule Synapse.Orchestrator.AgentConfigTest do
  use ExUnit.Case, async: true

  alias Synapse.Orchestrator.AgentConfig

  describe "new/1" do
    test "returns struct for specialist with required fields" do
      config = %{
        id: :demo_agent,
        type: :specialist,
        actions: [Sample.Action],
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      }

      assert {:ok, %AgentConfig{} = result} = AgentConfig.new(config)
      assert result.id == :demo_agent
      assert result.actions == [Sample.Action]
    end

    test "errors when specialist is missing actions" do
      config = %{
        id: :invalid_agent,
        type: :specialist,
        signals: %{subscribes: [:review_request], emits: [:review_result]}
      }

      assert {:error, %NimbleOptions.ValidationError{} = error} = AgentConfig.new(config)
      assert error.message =~ "specialist agents must define at least one action module"
    end
  end

  describe "signals with roles" do
    test "accepts signals with explicit roles" do
      config = %{
        id: :test_orchestrator,
        type: :orchestrator,
        signals: %{
          subscribes: [:task_request, :task_result],
          emits: [:task_summary],
          roles: %{
            request: :task_request,
            result: :task_result,
            summary: :task_summary
          }
        },
        orchestration: %{
          classify_fn: fn _ -> %{path: :default} end,
          spawn_specialists: [],
          aggregation_fn: fn _, _ -> %{} end
        }
      }

      assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
      assert validated.signals.roles.request == :task_request
      assert validated.signals.roles.result == :task_result
      assert validated.signals.roles.summary == :task_summary
    end

    test "infers default roles from topic names when not specified" do
      config = %{
        id: :test_orchestrator,
        type: :orchestrator,
        signals: %{
          subscribes: [:task_request, :task_result],
          emits: [:task_summary]
        },
        orchestration: %{
          classify_fn: fn _ -> %{path: :default} end,
          spawn_specialists: [],
          aggregation_fn: fn _, _ -> %{} end
        }
      }

      assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
      assert validated.signals.roles.request == :task_request
      assert validated.signals.roles.result == :task_result
      assert validated.signals.roles.summary == :task_summary
    end

    test "roles default to nil for specialist agents" do
      config = %{
        id: :test_specialist,
        type: :specialist,
        actions: [SomeAction],
        signals: %{
          subscribes: [:task_request],
          emits: [:task_result]
        }
      }

      assert {:ok, %AgentConfig{} = validated} = AgentConfig.new(config)
      assert validated.signals.roles == nil or validated.signals.roles == %{}
    end

    test "validates that role topics are in subscribes or emits" do
      config = %{
        id: :test_orchestrator,
        type: :orchestrator,
        signals: %{
          subscribes: [:task_request],
          emits: [:task_summary],
          roles: %{
            request: :task_request,
            result: :nonexistent_topic,
            summary: :task_summary
          }
        },
        orchestration: %{
          classify_fn: fn _ -> %{} end,
          spawn_specialists: [],
          aggregation_fn: fn _, _ -> %{} end
        }
      }

      assert {:error, _} = AgentConfig.new(config)
    end
  end

  describe "signals with dynamic topics" do
    test "validates topics against registry" do
      topic = :"agent_config_test_topic_#{System.unique_integer([:positive])}"

      :ok =
        Synapse.Signal.register_topic(topic,
          type: "test.#{topic}",
          schema: [id: [type: :string, required: true]]
        )

      config = %{
        id: :test_specialist,
        type: :specialist,
        actions: [SomeAction],
        signals: %{
          subscribes: [topic],
          emits: []
        }
      }

      assert {:ok, %AgentConfig{}} = AgentConfig.new(config)
    end

    test "rejects unregistered topics" do
      config = %{
        id: :test_specialist,
        type: :specialist,
        actions: [SomeAction],
        signals: %{
          subscribes: [:completely_unknown_topic],
          emits: []
        }
      }

      assert {:error, _} = AgentConfig.new(config)
    end
  end
end
