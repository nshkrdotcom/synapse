defmodule AxonCore.AxonBridge.Generator do
  @moduledoc """
  This module is responsible for generating gRPC code based on Elixir interface definitions.
  """

  def generate_proto(interface_def) do
    """
    Generates a .proto file based on the provided interface definition.

    ## Parameters

    - `interface_def`: A map representing the interface definition.

    ## Returns

    - `{:ok, proto_content}` if the .proto file is generated successfully.
    - `{:error, reason}` if an error occurs.
    """
    service_name = Map.get(interface_def, :service_name, "MyService")
    methods = Map.get(interface_def, :methods, [])

    proto_content = """
    syntax = "proto3";

    package axon;

    service #{service_name} {
      #{generate_methods(methods)}
    }

    #{generate_messages(methods)}
    """

    {:ok, proto_content}
  end

  defp generate_methods(methods) do
    Enum.map_join(methods, "\n", fn method ->
      "  rpc #{method.name} (#{method.request_type}) returns (#{method.response_type}) {};"
    end)
  end

  defp generate_messages(methods) do
    messages =
      methods
      |> Enum.flat_map(fn method ->
        [
          generate_message(method.request_type, method.request_fields),
          generate_message(method.response_type, method.response_fields)
        ]
      end)
      |> Enum.filter(fn message -> message != nil end)
      |> Enum.uniq_by(& &1.name)

    Enum.map_join(messages, "\n\n", & &1.content)
  end

  defp generate_message(message_name, fields) when is_binary(message_name) and is_list(fields) do
    message_content = """
    message #{message_name} {
      #{generate_message_fields(fields)}
    }
    """
    %{name: message_name, content: message_content}
  end
  defp generate_message(_, _), do: nil

  defp generate_message_fields(fields) do
    Enum.map_join(fields, "\n", fn {field_name, field_type} ->
      "  #{field_type} #{field_name} = 1;"
    end)
  end
end
