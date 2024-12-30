#!/usr/bin/env elixir

Mix.start()
Mix.shell(Mix.Shell.IO)

defmodule AxonCore.ProtobufSetup do
  def run do
    IO.puts("\nGenerating protobuf files...")
    python_project_path = Path.join(File.cwd!(), "script")
    command = "python -m grpc_tools.protoc"
    args = [
      "-I./script/src/grpc_server",
      "--python_out=./script/src/grpc_server",
      "--grpc_python_out=./script/src/grpc_server",
      "./script/src/grpc_server/hello.proto"
    ]

    case System.cmd("poetry", ["run", command] ++ args, cd: python_project_path, stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("Protobuf files generated successfully")
        IO.puts(output)
        :ok

      {error, _} ->
        IO.puts("Failed to generate protobuf files: #{error}")
        :error
    end
  end
end

AxonCore.ProtobufSetup.run()

AxonCore.ProtobufSetup.run()
