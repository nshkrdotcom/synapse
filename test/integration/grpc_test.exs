defmodule AxonCore.GrpcTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  test "gRPC connection test" do
    # Start the Python gRPC server
    {:ok, server_pid} = Task.Supervisor.start_child(AxonCore.TaskSupervisor, fn ->
      System.cmd("python3", ["script/src/grpc_server/server.py"])
    end)

    # Give the server some time to start
    Process.sleep(1000)

    # Create a gRPC client
    {:ok, client} = GRPC.Stub.new("localhost:50051", AxonCore.Grpc.Greeter.Stub)

    # Make a gRPC call
    request = %AxonCore.Grpc.HelloRequest{name: "Test"}
    {:ok, response} = GRPC.Stub.call(client, :say_hello, request)

    # Assert the response
    assert response.message == "Hello, Test!"

    # Stop the server
    Task.Supervisor.stop(server_pid)
  end
end
