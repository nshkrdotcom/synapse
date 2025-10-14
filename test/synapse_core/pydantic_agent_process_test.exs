defmodule SynapseCore.PydanticAgentProcessTest do
  use ExUnit.Case, async: true
  
  alias SynapseCore.PydanticAgentProcess
  alias SynapseCore.PydanticHTTPClient
  alias SynapseCore.PydanticToolRegistry

  @moduletag :capture_log

  setup do
    # Start the HTTP client and tool registry
    start_supervised!(PydanticHTTPClient)
    start_supervised!(PydanticToolRegistry)

    # Mock agent configuration
    config = %{
      name: "test_agent",
      python_module: "test_module",
      model: "gpt-4",
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
    test "starts agent process", %{config: config} do
      assert {:ok, pid} = PydanticAgentProcess.start_link(config)
      assert Process.alive?(pid)
    end

    test "registers agent with Python wrapper", %{config: config} do
      {:ok, _pid} = PydanticAgentProcess.start_link(config)
      # Wait for registration to complete
      Process.sleep(100)
      
      # Verify agent exists in Python wrapper (requires running wrapper)
      # This would be better with proper mocking
      assert {:ok, _} = PydanticHTTPClient.post(
        "http://localhost:#{config.port}/agents/#{config.name}",
        %{}
      )
    end
  end

  describe "message handling" do
    setup %{config: config} do
      {:ok, pid} = PydanticAgentProcess.start_link(config)
      {:ok, agent: pid}
    end

    test "sends message and receives response", %{config: config} do
      result = PydanticAgentProcess.run(
        config.name,
        "Hello",
        [],
        %{}
      )

      assert {:ok, %{result: _result, messages: messages}} = result
      assert is_list(messages)
    end

    test "streams responses", %{config: config} do
      {:ok, stream_pid} = PydanticAgentProcess.run_stream(
        config.name,
        "Hello",
        [],
        %{}
      )

      assert Process.alive?(stream_pid)

      # Collect streamed chunks
      chunks = collect_stream_chunks(stream_pid)
      assert length(chunks) > 0
    end

    test "handles tool calls", %{config: config} do
      # Register a test tool
      :ok = PydanticToolRegistry.register_tool(%{
        name: "test_tool",
        description: "A test tool",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "input" => %{"type" => "string"}
          },
          "required" => ["input"]
        },
        handler: fn %{"input" => input} -> "Processed: #{input}" end
      })

      result = PydanticAgentProcess.call_tool(
        config.name,
        "test_tool",
        %{"input" => "test"}
      )

      assert {:ok, "Processed: test"} = result
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
