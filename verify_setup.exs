#!/usr/bin/env elixir

Mix.start()
Mix.shell(Mix.Shell.IO)

defmodule Axon.Verify do
  require Logger
  alias AxonCore.{PythonEnvManager, PydanticSupervisor, PydanticAgentProcess}

  def run do
    IO.puts("\n=== Verifying Axon Setup ===\n")

    with :ok <- verify_environment(),
         :ok <- verify_supervisor(),
         :ok <- verify_agent() do
      
      IO.puts("""
      \n✅ Verification completed successfully!
      
      Your Axon installation is ready to use.
      Run 'iex -S mix' to start developing with Axon.
      
      Quick start:
      ```elixir
      # Start an agent
      config = %{
        name: "my_agent",
        python_module: "translation_agent",
        model: "gemini-1.5-pro",
        system_prompt: "You are a helpful assistant."
      }
      
      {:ok, pid} = AxonCore.PydanticSupervisor.start_agent(config)
      
      # Use the agent
      {:ok, result} = AxonCore.PydanticAgentProcess.run(
        "my_agent",
        "Translate 'Hello' to Spanish"
      )
      ```
      """)
    else
      {:error, stage, error} ->
        IO.puts("\n❌ Verification failed at stage: #{stage}")
        AxonCore.Error.log_error(error)
        System.halt(1)
    end
  end

  defp verify_environment do
    IO.puts("Checking Python environment...")
    try do
      PythonEnvManager.ensure_env!()
      IO.puts("✓ Python environment OK")
      :ok
    rescue
      e -> {:error, :environment, e}
    end
  end

  defp verify_supervisor do
    IO.puts("\nStarting supervisor...")
    case PydanticSupervisor.start_link([]) do
      {:ok, _pid} ->
        IO.puts("✓ Supervisor started")
        :ok
      {:error, reason} ->
        {:error, :supervisor, reason}
    end
  end

  defp verify_agent do
    IO.puts("\nTesting agent creation...")
    
    config = %{
      name: "test_agent",
      python_module: "translation_agent",
      model: "gemini-1.5-pro",
      system_prompt: "You are a test assistant."
    }

    case PydanticSupervisor.start_agent(config) do
      {:ok, pid} ->
        IO.puts("✓ Agent started")
        verify_agent_execution(config.name)
      error ->
        {:error, :agent_start, error}
    end
  end

  defp verify_agent_execution(name) do
    IO.puts("\nTesting agent execution...")
    
    case PydanticAgentProcess.run(name, "Echo: test", [], %{}) do
      {:ok, result} ->
        IO.puts("✓ Agent execution successful")
        :ok
      error ->
        {:error, :agent_execution, error}
    end
  end
end

Axon.Verify.run()
