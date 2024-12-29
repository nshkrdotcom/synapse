# defmodule AxonCore.AgentGrpcServer do
#   use GRPC.Server, service: AxonCore.AgentService.Service

#   def run_sync(request, _stream) do
#     # Implement as before, using gRPC messages instead of HTTP
#   end

#   def run_stream(request, stream) do
#     agent_id = request.agent_id

#     case AxonCore.AgentRegistry.lookup(agent_id) do
#       {:ok, agent_pid} ->
#         send(agent_pid, {:grpc_stream_request, request, stream})
#         {:ok, %{}}

#       {:error, :not_found} ->
#         raise GRPC.RPCError, status: :not_found, message: "Agent not found: #{agent_id}"
#     end
#   end
# end
