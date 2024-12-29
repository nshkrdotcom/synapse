defmodule AxonCore.PydanticIntegrationTest do
  use ExUnit.Case
  
  alias AxonCore.{
    PydanticAgentProcess,
    PydanticHTTPClient,
    PydanticToolRegistry,
    PydanticSupervisor
  }

  @moduletag :integration
  @moduletag :capture_log

  setup_all do
    # Start the supervisor which starts all components
    start_supervised!(PydanticSupervisor)

    # Wait for Python server to be ready
    Process.sleep(1000)

    :ok
  end

  setup do
    # Basic agent configuration for tests
    config = %{
      name: "test_agent_#{:rand.uniform(1000)}",
      python_module: "translation_agent",
      model: "gemini-1.5-pro",
      port: 8000,
      system_prompt: "You are a test assistant.",
      tools: [
        %{
          name: "test_tool",
          description: "A test tool",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "input" => %{"type" => "string"}
            },
            "required" => ["input"]
          }
        }
      ],
      result_type: %{
        "type" => "object",
        "properties" => %{
          "output" => %{"type" => "string"}
        }
      },
      extra_env: []
    }

    {:ok, config: config}
  end

  describe "agent lifecycle" do
    test "complete agent lifecycle", %{config: config} do
      # 1. Start agent
      {:ok, pid} = PydanticSupervisor.start_agent(config)
      assert Process.alive?(pid)

      # 2. Verify agent registration
      assert config.name in (PydanticSupervisor.list_agents() |> Enum.map(&elem(&1, 0)))

      # 3. Stop agent
      assert :ok = PydanticSupervisor.stop_agent(config.name)
      refute config.name in (PydanticSupervisor.list_agents() |> Enum.map(&elem(&1, 0)))
    end

    test "handles agent crashes gracefully", %{config: config} do
      {:ok, pid} = PydanticSupervisor.start_agent(config)
      
      # Simulate crash
      Process.exit(pid, :kill)
      
      # Wait for restart
      Process.sleep(100)
      
      # Agent should be restarted
      new_pid = Process.whereis(String.to_atom(config.name))
      assert Process.alive?(new_pid)
      assert new_pid != pid
    end
  end

  describe "message handling" do
    setup %{config: config} do
      {:ok, _pid} = PydanticSupervisor.start_agent(config)
      :ok
    end

    test "handles synchronous messages", %{config: config} do
      result = PydanticAgentProcess.run(
        config.name,
        "Translate 'Hello' to Spanish",
        [],
        %{}
      )

      assert {:ok, %{result: result}} = result
      assert is_map(result)
      assert result["translated_text"] == "¡Hola!"
    end

    test "handles streaming messages", %{config: config} do
      {:ok, stream_pid} = PydanticAgentProcess.run_stream(
        config.name,
        "Tell me a long story about a cat",
        [],
        %{}
      )

      chunks = collect_stream_chunks(stream_pid)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &is_binary/1)
    end

    test "handles errors gracefully", %{config: config} do
      result = PydanticAgentProcess.run(
        config.name,
        "", # Empty prompt should cause an error
        [],
        %{}
      )

      assert {:error, _reason} = result
    end
  end

  describe "tool integration" do
    setup %{config: config} do
      {:ok, _pid} = PydanticSupervisor.start_agent(config)

      # Register test tools
      :ok = PydanticToolRegistry.register_tool(%{
        name: "echo",
        description: "Echoes input",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "input" => %{"type" => "string"}
          },
          "required" => ["input"]
        },
        handler: fn %{"input" => input} -> input end
      })

      :ok = PydanticToolRegistry.register_tool(%{
        name: "async_tool",
        description: "Async operation",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "delay" => %{"type" => "integer"}
          },
          "required" => ["delay"]
        },
        handler: fn %{"delay" => delay} ->
          Process.sleep(delay)
          "Done after #{delay}ms"
        end
      })

      :ok
    end

    test "executes tools successfully", %{config: config} do
      result = PydanticAgentProcess.call_tool(
        config.name,
        "echo",
        %{"input" => "test"}
      )

      assert {:ok, "test"} = result
    end

    test "handles tool errors", %{config: config} do
      result = PydanticAgentProcess.call_tool(
        config.name,
        "nonexistent_tool",
        %{}
      )

      assert {:error, _} = result
    end

    test "handles async tools", %{config: config} do
      result = PydanticAgentProcess.call_tool(
        config.name,
        "async_tool",
        %{"delay" => 100}
      )

      assert {:ok, "Done after 100ms"} = result
    end
  end

  describe "error handling" do
    test "handles network errors", %{config: config} do
      # Use invalid port
      config = %{config | port: 9999}
      
      {:ok, _pid} = PydanticSupervisor.start_agent(config)
      
      result = PydanticAgentProcess.run(
        config.name,
        "Hello",
        [],
        %{}
      )

      assert {:error, :network_error, _} = result
    end

    test "handles timeouts", %{config: config} do
      {:ok, _pid} = PydanticSupervisor.start_agent(config)
      
      result = PydanticAgentProcess.run(
        config.name,
        "Sleep for 10 seconds", # Should trigger timeout
        [],
        %{}
      )

      assert {:error, :timeout, _} = result
    end

    test "handles validation errors", %{config: config} do
      {:ok, _pid} = PydanticSupervisor.start_agent(config)
      
      result = PydanticAgentProcess.call_tool(
        config.name,
        "echo",
        %{"wrong_param" => "test"} # Invalid parameters
      )

      assert {:error, :validation_error, _} = result
    end
  end

  describe "system monitoring" do
    test "provides system status" do
      status = PydanticSupervisor.status()
      
      assert is_map(status)
      assert Map.has_key?(status, :http_client)
      assert Map.has_key?(status, :tool_registry)
      assert Map.has_key?(status, :agent_supervisor)
    end

    test "tracks agent metrics", %{config: config} do
      {:ok, _pid} = PydanticSupervisor.start_agent(config)
      
      # Run some operations to generate metrics
      PydanticAgentProcess.run(config.name, "Hello", [], %{})
      PydanticAgentProcess.call_tool(config.name, "echo", %{"input" => "test"})
      
      # TODO: Add actual metric assertions once metrics are implemented
      # This is a placeholder for future metric testing
    end
  end

  # Helper Functions

  defp collect_stream_chunks(pid, chunks \\ []) do
    receive do
      {:chunk, chunk} ->
        collect_stream_chunks(pid, [chunk | chunks])
      {:end_stream} ->
        Enum.reverse(chunks)
      {:error, _reason} ->
        Enum.reverse(chunks)
    after
      5000 -> Enum.reverse(chunks)
    end
  end
end
