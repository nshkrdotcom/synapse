defmodule AxonCore.GeneratorTest do
  use ExUnit.Case, async: true

  alias AxonCore.AxonBridge.Generator

  test "generate_proto/1 generates a valid .proto file" do
    interface_def = %{
      service_name: "MyTestService",
      methods: [
        %{
          name: "MyMethod",
          request_type: "MyRequest",
          response_type: "MyResponse",
          request_fields: [
            {"name", "string"},
            {"age", "int32"}
          ],
          response_fields: [
            {"greeting", "string"}
          ]
        }
      ]
    }

    {:ok, proto_content} = Generator.generate_proto(interface_def)

    expected_proto_content = """
    syntax = "proto3";

    package axon;

    service MyTestService {
      rpc MyMethod (MyRequest) returns (MyResponse) {};
    }

    message MyRequest {
      string name = 1;
      int32 age = 1;
    }

    message MyResponse {
      string greeting = 1;
    }
    """

    assert proto_content == expected_proto_content
  end
end
