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
          verify_python_env(build_path)
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

    defp verify_python_env(build_path) do
      IO.puts("\nVerifying Python environment with Poetry...")
      path = System.get_env("HOME") <> "/.local/bin:" <> System.get_env("PATH")
      System.put_env("PATH", path)


      # Check if Poetry is installed
      case System.cmd("poetry", ["--version"], stderr_to_stdout: true) do
        {_, 0} ->
          IO.puts("✓ Poetry is installed")

          python_project_path = Path.join([File.cwd!(), "apps", "axon_python"])

          # Use Poetry to run pip and install the package in editable mode
          IO.puts("Installing axon_python package using Poetry...")

          # Use poetry run to execute pip install within the virtual environment
          case System.cmd("poetry", ["run", "python", "-m", "pip", "install", "-e", "."],
             cd: Path.join(python_project_path, "src"),
             stderr_to_stdout: true
           ) do
            {output, 0} ->
              IO.puts("✓ Installed axon_python package using Poetry")
              IO.puts(output)

              # Verify we can import the module using Poetry
              case System.cmd("poetry", ["run", "python", "-c", "import axon_python.agent_wrapper"],
                 cd: python_project_path,
                 stderr_to_stdout: true
               ) do
                {_, 0} ->
                  IO.puts("✓ Successfully imported axon_python.agent_wrapper using Poetry")
                  start_axon_core(build_path)
                {error, _} ->
                  IO.puts("\n❌ Failed to import axon_python.agent_wrapper using Poetry")
                  IO.puts("Error: #{error}")
                  System.halt(1)
              end
            {error, _} ->
              IO.puts("\n❌ Failed to install axon_python package using Poetry")
              IO.puts("Error: #{error}")
              System.halt(1)
          end
        {error, _} ->
          IO.puts("\n❌ Poetry is not installed or not in the PATH")
          IO.puts("Error: #{error}")
          IO.puts("Please install Poetry: https://python-poetry.org/docs/#installation")
          System.halt(1)
      end
    end

    defp start_axon_core(build_path) do
      IO.puts("\nStarting axon_core...")
      case Application.ensure_all_started(:axon_core) do
        {:ok, started_apps} ->
          IO.puts("✓ Started axon_core and dependencies: #{inspect(started_apps)}")
          verify_python_env_final(build_path)
        {:error, {app, reason}} ->
          IO.puts("\n❌ Failed to start #{app}")
          IO.puts("Error details:")
          IO.puts("  - Application: #{app}")
          IO.puts("  - Reason: #{inspect(reason, pretty: true)}")
          IO.puts("  - Dependencies: #{inspect(Application.spec(app, :applications), pretty: true)}")
          System.halt(1)
      end
    end

    defp verify_python_env_final(build_path) do
      IO.puts("\nVerifying Python environment...")
      IO.puts("\nBuild path: #{inspect(build_path)}")
      case AxonCore.PythonEnvManager.ensure_env!() do
        :ok ->
          venv_path = AxonCore.PythonEnvManager.venv_path()
          IO.puts("✓ Python environment verified at #{venv_path}")

          # Use Poetry to run the Python script
          python_package_dir = Path.join([File.cwd!(), "apps", "axon_core", "priv", "python"])

          # Verify Python modules can be imported using Poetry
          test_import_cmd = """
          import sys
          import agents.example_agent
          import fastapi
          import uvicorn
          print('✓ All required Python modules can be imported')
          """

          case System.cmd("poetry", ["run", "python", "-c", test_import_cmd],
            cd: python_package_dir
          ) do
            {output, 0} ->
              IO.puts(output)
              IO.puts("\n=== Setup Complete! ===")
              IO.puts("\nNext step: Start the Elixir shell with:")
              IO.puts("  iex -S mix")
              :ok
            {error, _} ->
              IO.puts("\n❌ Python module verification failed")
              IO.puts("Error: #{error}")
              System.halt(1)
          end
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
