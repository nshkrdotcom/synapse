#!/usr/bin/env elixir

# Initialize Mix
Mix.start()
Mix.shell(Mix.Shell.IO)

# Load the umbrella project
Mix.Project.in_project(:axon, ".", fn _module ->
  IO.puts("\n=== Verifying Axon Setup ===\n")
  
  # Ensure dependencies are compiled
  IO.puts("Compiling dependencies...")
  Mix.Task.run("deps.compile")
  Mix.Task.run("compile")
  
  # Add build paths to code path to ensure we can find all modules
  build_path = Path.join([File.cwd!(), "_build", "dev", "lib"])
  for app <- ~w(axon axon_core axon_python finch mint)a do
    Code.prepend_path(Path.join([build_path, Atom.to_string(app), "ebin"]))
  end

  defmodule Verify do
    require Logger

    def run(build_path) do
      verify_environment(build_path)
    end

    defp verify_environment(build_path) do
      IO.puts("Starting core dependencies...")
      
      # First try to start just finch
      case Application.ensure_all_started(:finch) do
        {:ok, finch_apps} ->
          IO.puts("✓ Started Finch and dependencies: #{inspect(finch_apps)}")
          start_axon_core(build_path)
        {:error, {app, reason}} ->
          IO.puts("\n❌ Failed to start #{app}")
          IO.puts("Error details:")
          IO.puts("  - Application: #{app}")
          IO.puts("  - Reason: #{inspect(reason, pretty: true)}")
          
          # Check if the .app file exists
          app_path = Path.join([build_path, Atom.to_string(app), "ebin", "#{app}.app"])
          if not File.exists?(app_path) do
            IO.puts("\nDiagnostics:")
            IO.puts("  - Expected .app file not found: #{app_path}")
            IO.puts("  - Build directory contents:")
            case File.ls(build_path) do
              {:ok, files} -> Enum.each(files, &IO.puts("    - #{&1}"))
              {:error, reason} -> IO.puts("    Error reading directory: #{inspect(reason)}")
            end
          end
          
          IO.puts("\nTroubleshooting steps:")
          IO.puts("1. Try recompiling dependencies: mix deps.compile --force")
          IO.puts("2. Check if #{app}.app exists in _build/dev/lib/#{app}/ebin/")
          IO.puts("3. Try cleaning build: mix clean && mix deps.clean --all")
          System.halt(1)
      end
    end

    defp start_axon_core(build_path) do
      IO.puts("\nStarting axon_core...")
      case Application.ensure_all_started(:axon_core) do
        {:ok, started_apps} ->
          IO.puts("✓ Started axon_core and dependencies: #{inspect(started_apps)}")
          verify_python_env(build_path)
        {:error, {app, reason}} ->
          IO.puts("\n❌ Failed to start #{app}")
          IO.puts("Error details:")
          IO.puts("  - Application: #{app}")
          IO.puts("  - Reason: #{inspect(reason, pretty: true)}")
          IO.puts("  - Dependencies: #{inspect(Application.spec(app, :applications), pretty: true)}")
          System.halt(1)
      end
    end

    defp verify_python_env(build_path) do
      IO.puts("\nVerifying Python environment...")
      case AxonCore.PythonEnvManager.ensure_env!() do
        :ok ->
          venv_path = AxonCore.PythonEnvManager.venv_path()
          IO.puts("✓ Python environment verified at #{venv_path}")
          IO.puts("\n=== Setup Complete! ===")
          IO.puts("\nNext step: Start the Elixir shell with:")
          IO.puts("  iex -S mix")
          :ok
        {:error, reason} -> 
          IO.puts("\n❌ Python environment verification failed")
          IO.puts("Error: #{inspect(reason)}")
          System.halt(1)
      end
    end
  end

  # Run verification
  Verify.run(build_path)
end)
