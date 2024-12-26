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

defmodule AxonCore.AgentProcessTest do
  use ExUnit.Case, async: true

  alias AxonCore.AgentProcess

  # Mock HTTPClient for testing purposes
  defp http_client_mock(response) do
    HTTPoisonMock = defmock("AxonCore.HTTPClient", for: HTTPClient)
    expect(HTTPoisonMock, :post, fn _, _, _ -> response end)
    HTTPoisonMock
  end

  describe "send_message/2" do
    test "returns the result on successful run_sync" do
      # Start the agent process
      {:ok, agent_pid} = AgentProcess.start_link(name: "test_agent", python_module: "test_agent", model: "test_model", port: 8081)

      # Mock the HTTP response from the Python agent
      mock_response = %{
        status_code: 200,
        body: Jason.encode!(%{
          "result" => %{"message" => "Test result"},
          "usage" => %{"requests" => 1, "request_tokens" => 10, "response_tokens" => 5, "total_tokens" => 15}
        })
      }

      # Override the HTTPClient with the mock
      with_mock HTTPClient, [post: fn _, _, _ -> {:ok, mock_response} end] do
        # Send a message to the agent
        {:ok, result, usage} = AgentProcess.send_message("test_agent", %{prompt: "test prompt"})

        # Assert the result
        assert result == %{"message" => "Test result"}
        assert usage == %{requests: 1, request_tokens: 10, response_tokens: 5, total_tokens: 15}
      end
    end

    # Add more test cases for error handling, streaming, etc.
  end
end
