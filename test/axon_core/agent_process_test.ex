# defmodule AxonCore.AgentProcessTest do
#   use ExUnit.Case, async: true

#   alias AxonCore.AgentProcess

#   describe "run_sync/2" do
#     test "successfully processes a request and returns the result" do
#       {:ok, agent_pid} = AgentProcess.start_link(name: "test_agent", python_module: "test_agent", model: "test_model", port: 50051)

#       # Mock the HTTPClient to return a successful response
#       HTTPClientMock = defmock("Elixir.AxonCore.HTTPClient", for: HTTPClient)
#       expect(HTTPClientMock, :post, fn _, _, _ -> {:ok, %{status_code: 200, body: Jason.encode!(%{result: "Test Result", usage: %{requests: 1}})}} end)

#       # Send a message to the agent
#       {:ok, result, usage} = AgentProcess.send_message("test_agent", %{prompt: "test prompt"})

#       # Assert the result and usage
#       assert result == "Test Result"
#       assert usage == %{requests: 1}
#     end

#     # Add more test cases for error handling, streaming, etc.
#   end
# end


# test/axon_core/agent_process_test.exs

# defmodule AxonCore.AgentProcessTest do
#   use ExUnit.Case, async: true

#   alias AxonCore.AgentProcess
#   alias AxonCore.HTTPClient
#   import Mox

#   # Mock HTTPClient for testing purposes
#   defp http_client_mock(response) do
#     HTTPoisonMock = defmock("AxonCore.HTTPClient", for: HTTPClient)
#     expect(HTTPoisonMock, :post, fn _, _, _ -> response end)
#     HTTPoisonMock
#   end

#   describe "send_message/2" do
#     test "returns the result on successful run_sync" do
#       # Start the agent process
#       {:ok, agent_pid} = AgentProcess.start_link(name: "test_agent", python_module: "test_agent", model: "test_model", port: 8081)

#       # Mock the HTTP response from the Python agent
#       mock_response = %{
#         status_code: 200,
#         body: Jason.encode!(%{
#           "result" => %{"message" => "Test result"},
#           "usage" => %{"requests" => 1, "request_tokens" => 10, "response_tokens" => 5, "total_tokens" => 15}
#         })
#       }

#       # Override the HTTPClient with the mock
#       with_mock HTTPClient, [post: fn _, _, _ -> {:ok, mock_response} end] do
#         # Send a message to the agent
#         {:ok, result, usage} = AgentProcess.send_message("test_agent", %{prompt: "test prompt"})

#         # Assert the result
#         assert result == %{"message" => "Test result"}
#         assert usage == %{requests: 1, request_tokens: 10, response_tokens: 5, total_tokens: 15}
#       end
#     end

#     # Add more test cases for error handling, streaming, etc.
#   end

#   test "agent calls a tool and receives the result", %{agent_pid: agent_pid} do
#     # Mock HTTPClient.post to simulate the Python agent calling a tool
#     HTTPClientMock = defmock("AxonCore.HTTPClient", for: HTTPClient)
#     expect(HTTPClientMock, :post, fn _url, _headers, body ->
#       # Assert that the request is for a tool call
#       assert %{
#                "tool_name" => "some_tool",
#                "args" => %{"arg1" => "value1", "arg2" => 2}
#              } = JSONCodec.decode!(body)

#       # Return a successful response with a result
#       {:ok, %{status_code: 200, body: JSONCodec.encode!(%{result: "Tool called successfully"})}}
#     end)

#     # Send a message to the agent that will trigger a tool call
#     ref = make_ref()
#     send(agent_pid, {:call_tool, "some_tool", %{"arg1" => "value1", "arg2" => 2}, ref})

#     # Wait for the tool result
#     assert_receive {:tool_result, ^ref, result}

#     # Assert the result
#     assert result == "Tool called successfully"


# end



# axon_core/test/axon_core/agent_process_test.exs

defmodule AxonCore.AgentProcessTest do
  use ExUnit.Case, async: true

  alias AxonCore.AgentProcess
  alias AxonCore.HTTPClient
  import Mox

  # Mock HTTPClient for testing purposes
  def setup(_) do
    HTTPClientMock = defmock("AxonCore.HTTPClientMock", for: HTTPClient)
    Mox.stub_with(HTTPClient, HTTPClientMock)
    # Start the agent process with necessary configuration
    {:ok, agent_pid} =
      AgentProcess.start_link(
        name: "test_agent",
        python_module: "agents.example_agent",
        model: "openai:gpt-4o",
        port: 8089,
        extra_env: []
      )

    {:ok, agent_pid: agent_pid}
  end

  describe "handle_call/3 :call_tool" do
    # test "correctly calls a Python tool and returns the result", %{agent_pid: agent_pid} do
    #   # Define the tool call details
    #   tool_name = "some_tool"
    #   tool_args = %{"arg1" => "hello", "arg2" => 123}
    #   request_id = "unique_request_id"

    #   # Mock the HTTP POST request to simulate the Python agent's response
    #   expected_response = {:ok, %{status_code: 200, body: Jason.encode!(%{result: "Tool called successfully"})}}
    #   expect(HTTPClientMock, :post, fn _url, _headers, body ->
    #     # Assert the structure of the body being sent to the Python agent
    #     assert Jason.decode!(body) == %{"tool_name" => tool_name, "args" => tool_args}

    #     # Return the mocked response
    #     expected_response
    #   end)

    #   # Send the call_tool message and capture the reply
    #   assert {:ok, result} =
    #            AgentProcess.call_tool(agent_pid, tool_name, tool_args)

    #   # Assert the result
    #   assert result == "Tool called successfully"
    # end
    # test "correctly calls a Python tool and returns the result", %{agent_pid: agent_pid} do
    #   # Start the agent process with necessary configuration
    #   {:ok, agent_pid} =
    #     AgentProcess.start_link(
    #       name: "test_agent",
    #       python_module: "test_agent",
    #       model: "test_model",
    #       port: 8081,
    #       extra_env: []
    #     )

    #   # Define the tool call details
    #   tool_name = "some_tool"
    #   tool_args = %{"arg1" => "hello", "arg2" => 123}

    #   # Mock the HTTP POST request to simulate the Python agent's response
    #   Mox.expect(HTTPClientMock, :post, fn _url, _headers, body ->
    #     # Assert the structure of the body being sent to the Python agent
    #     assert Jason.decode!(body) == %{"tool_name" => tool_name, "args" => tool_args}

    #     # Return a successful response with a result
    #     {:ok, %{status_code: 200, body: Jason.encode!(%{result: "Tool called successfully"})}}
    #   end)

    #   # Send the call_tool message to the agent process
    #   assert {:ok, result} = AgentProcess.call_tool(agent_pid, tool_name, tool_args)

    #   # Assert the result
    #   assert result == "Tool called successfully"
    #   Mox.verify(HTTPClientMock)
    # end
    ## OR:
    test "correctly calls a Python tool and returns the result", %{agent_pid: agent_pid} do
      # Define the tool call details
      tool_name = "some_tool"
      tool_args = %{"arg1" => "hello", "arg2" => 123}

      # Mock the HTTP POST request to simulate the Python agent's response
      expect(HTTPClientMock, :post, fn _url, _headers, body ->
        # Assert the structure of the body being sent to the Python agent
        assert Jason.decode!(body) == %{"tool_name" => tool_name, "args" => tool_args}

        # Return a successful response with a result
        {:ok, %{status_code: 200, body: Jason.encode!(%{result: "Tool called successfully"})}}
      end)

      # Send the call_tool message to the agent process
      assert {:ok, result} = AgentProcess.call_tool(agent_pid, tool_name, tool_args)

      # Assert the result
      assert result == "Tool called successfully"
      Mox.verify(HTTPClientMock)
    end

    test "handles tool not found error", %{agent_pid: agent_pid} do
      tool_name = "nonexistent_tool"
      tool_args = %{}

      # Mock HTTP POST to return a 404 error indicating tool not found
      expect(HTTPClientMock, :post, fn _url, _headers, body ->
        assert Jason.decode!(body) == %{"tool_name" => tool_name, "args" => tool_args}
        {:ok, %{status_code: 404, body: Jason.encode!(%{detail: "Tool not found"})}}
      end)

      # Call the tool and expect an error
      assert {:error, reason} = AgentProcess.call_tool(agent_pid, tool_name, tool_args)
      assert reason == "Tool call failed with status code: 404"
    end

    test "handles invalid arguments error", %{agent_pid: agent_pid} do
      tool_name = "some_tool"
      tool_args = %{"invalid_arg" => "invalid"}

      # Mock HTTP POST to return a 400 error indicating invalid arguments
      expect(HTTPClientMock, :post, fn _url, _headers, body ->
        assert Jason.decode!(body) == %{"tool_name" => tool_name, "args" => tool_args}
        {:ok, %{status_code: 400, body: Jason.encode!(%{detail: "Invalid arguments"})}}
      end)

      # Call the tool and expect an error
      assert {:error, reason} = AgentProcess.call_tool(agent_pid, tool_name, tool_args)
      assert reason == "Tool call failed with status code: 400"
    end

    test "handles Python agent crash", %{agent_pid: agent_pid} do
      tool_name = "some_tool"
      tool_args = %{}

      # Mock HTTP POST to simulate a connection error (agent crash)
      expect(HTTPClientMock, :post, fn _, _, _ -> {:error, :econnrefused} end)

      # Call the tool and expect an error
      assert {:error, reason} = AgentProcess.call_tool(agent_pid, tool_name, tool_args)
      assert reason == :econnrefused # Or a more specific error message
    end
    # Add more test cases for other error scenarios as needed


  end


  describe "send_message/2" do
    test "correctly processes request and returns result", %{agent_pid: agent_pid} do
      # Start the agent process with necessary configuration
      # {:ok, agent_pid} =
      #   AgentProcess.start_link(
      #     name: "test_agent",
      #     python_module: "agents.example_agent",
      #     model: "openai:gpt-4o",
      #     port: 8089,
      #     extra_env: []
      #   )

      # Mock the HTTP POST request to simulate the Python agent's response
      expected_response =
        {:ok,
         %{
           status_code: 200,
           body:
             Jason.encode!(%{
               "result" => %{response: "Test response"},
               "usage" => %{requests: 1, request_tokens: 10, response_tokens: 5, total_tokens: 15},
               "messages" => []
             })
         }}

      expect(HTTPClientMock, :post, fn _url, _headers, body ->
        request = JSONCodec.decode!(body)
        assert request["prompt"] == "test prompt"
        expected_response
      end)

      # Send a synchronous run request
      {:ok, result, usage} = AgentProcess.send_message("test_agent", %{prompt: "test prompt"})

      # Assert the result and usage
      assert result == %{"response" => "Test response"}
      assert usage == %{"requests" => 1, "request_tokens" => 10, "response_tokens" => 5, "total_tokens" => 15}
      Mox.verify(HTTPClientMock)
    end

    # Add more test cases for error handling, streaming, etc.
  end

end
