#!/usr/bin/env elixir

# Start Mix and load dependencies
Mix.start()
Mix.shell(Mix.Shell.IO)

# Ensure we can load our dependencies
Application.ensure_all_started(:jason)
Code.prepend_path("_build/dev/lib/axon/ebin")
Code.prepend_path("_build/dev/lib/axon_core/ebin")
Code.prepend_path("_build/dev/lib/axon_python/ebin")

defmodule Axon.Verify do
  @moduledoc """
  Verification module for Axon setup.
  """

  require Logger
  alias AxonCore.Error.PythonEnvError

  def run do
    IO.puts("\n=== Verifying Axon Setup ===\n")

    stages = [
      {"environment", &verify_environment/0},
      {"agent", &verify_agent/0},
      {"agent execution", &verify_agent_execution/1}
    ]

    try do
      Enum.reduce_while(stages, nil, fn {stage, verify_fn}, acc ->
        IO.puts("Checking #{stage}...")
        try do
          case verify_fn.(acc) do
            {:ok, result} -> {:cont, result}
            {:error, error} ->
              IO.puts("\n❌ Verification failed at stage: #{stage}")
              raise error
          end
        rescue
          error ->
            IO.puts("\n❌ Verification failed at stage: #{stage}")
            Logger.error("Error: #{inspect(error)}")
            System.halt(1)
        end
      end)

      IO.puts("\n✓ All verifications passed!")
      :ok
    rescue
      error ->
        Logger.error("Error: #{inspect(error)}")
        System.halt(1)
    end
  end

  defp verify_environment do
    try do
      # First ensure axon_core is started since we need its PythonEnvManager
      {:ok, _} = Application.ensure_all_started(:axon_core)
      
      # Verify Python environment
      case AxonCore.PythonEnvManager.ensure_env!() do
        :ok -> {:ok, nil}
        {:error, reason} -> {:error, PythonEnvError.new(reason)}
      end
    rescue
      error -> {:error, error}
    end
  end

  defp verify_agent do
    try do
      # Start the main Axon application which includes agent supervision
      {:ok, _} = Application.ensure_all_started(:axon)

      # Start a test agent
      {:ok, _pid} = Axon.Agent.start_link(
        name: "test_agent",
        python_module: "agents.example_agent",
        model: "test:model",
        port: 5000,
        extra_env: [{"PYTHONPATH", "./apps/axon_python/src"}]
      )

      {:ok, "test_agent"}
    rescue
      error -> {:error, error}
    end
  end

  defp verify_agent_execution(agent_name) do
    try do
      # Try sending a simple message to the agent
      case Axon.Agent.Server.send_message(
        agent_name,
        %{
          "prompt" => "Hello, agent!",
          "message_history" => []
        }
      ) do
        {:ok, _result} -> {:ok, nil}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error -> {:error, error}
    end
  end
end

# Run the verification
Axon.Verify.run()
