defmodule Axon.AgentService do
  @moduledoc """
  Stub module for gRPC service.
  """

  defmodule Stub do
    def run_sync(channel, request) do
      # Temporary mock implementation
      {:ok, %Axon.RunResponse{
        result: "Mock response",
        usage: %Axon.Usage{
          request_tokens: 10,
          response_tokens: 20,
          total_tokens: 30
        }
      }}
    end
  end
end
