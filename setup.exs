#!/usr/bin/env elixir

Mix.start()
Mix.shell(Mix.Shell.IO)

defmodule Axon.Setup.Error do
  defexception [:message, :reason, :context]

  def new(reason, context \\ %{}) do
    message =
      case reason do
        :python_not_found ->
          "Python interpreter not found. Please ensure Python 3.10 or higher is installed."
        :version_mismatch ->
          "Python version mismatch. Found: #{context[:found]}, Required: #{context[:required]}"
        :poetry_not_found ->
          "Poetry not found. Attempting to install Poetry."
        :poetry_install_failed ->
          "Failed to install Poetry: #{context[:error]}"
        :venv_creation_failed ->
          "Failed to create virtual environment with Poetry: #{context[:error]}"
        :dependency_install_failed ->
          "Failed to install Python dependencies with Poetry: #{context[:error]}"
        :elixir_deps_failed ->
          "Failed to fetch Elixir dependencies: #{context[:error]}"
        :compile_failed ->
          "Failed to compile project: #{context[:error]}"
        _ ->
          "Unknown error: #{inspect(reason)}"
      end

    %__MODULE__{
      message: message,
      reason: reason,
      context: context
    }
  end
end

defmodule Axon.Setup do
  @colors %{
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    reset: "\e[0m"
  }

  def run do
    IO.puts("\n#{color("=== Setting up Axon development environment ===", :blue)}\n")

    with :ok <- check_elixir_version(),
         :ok <- check_python(),
         :ok <- ensure_poetry_installed(),
         :ok <- setup_python_environment(),
         :ok <- fetch_elixir_deps(),
         :ok <- compile_project() do
      IO.puts("""
      \n#{color("✓ Setup completed successfully!", :green)}

      Run 'iex -S mix' to start the application.
      """)
    else
      {:error, stage, message} when is_binary(stage) and is_binary(message) ->
        IO.puts("\n#{color("❌ Setup failed at stage: #{stage}", :red)}")
        IO.puts("#{color("Error: #{message}", :red)}")
        System.halt(1)
      {:error, stage, message}  ->
        IO.puts("\n#{color("❌ Setup failed at stage: #{stage}", :red)}")
        IO.puts("#{color("Error: #{message}", :red)}")
        System.halt(1)
        {:error, error} when is_exception(error) ->
        print_error(error)
        System.halt(1)
      {:error, message} ->
        IO.puts("\n#{color("✗ Error:", :red)} #{message}")
        System.halt(1)
    end
  end

  defp check_elixir_version do
    version = System.version()
    min_version = "1.14.0"

    if Version.match?(version, ">= #{min_version}") do
      IO.puts("#{color("✓", :green)} Elixir version #{version} OK")
      :ok
    else
      {:error, :elixir_version, "Elixir version must be >= #{min_version} (found: #{version})"}
    end
  end

  defp check_python do
    IO.puts("\nChecking Python installation...")
    min_version = "3.10.0"

    case System.cmd("python3", ["--version"]) do
      {version, 0} ->
        version = version |> String.trim() |> String.split(" ") |> List.last()
        if Version.match?(version, ">= #{min_version}") do
          IO.puts("#{color("✓", :green)} Python version #{version} OK")
          :ok
        else
          {:error, :python_version, "Python version #{version} is below minimum required version #{min_version}"}
        end
      _ ->
        {:error, :python_not_found, "Python 3 not found. Please install Python 3.10 or higher"}
    end
  end

  defp ensure_poetry_installed do
    IO.puts("\nEnsuring Poetry is installed...")
    try do
      case System.cmd("poetry", ["--version"], stderr_to_stdout: true) do
        {_, 0} ->
          IO.puts("#{color("✓", :green)} Poetry is already installed")
          :ok
        _ ->
          install_poetry()
      end
    rescue
      e in ErlangError ->
        case e do
          %ErlangError{original: :enoent} ->
            IO.puts(
              "#{color("!", :yellow)} Poetry not found. Attempting to install Poetry automatically..."
            )
            install_poetry()
          _ ->
            {:error, :poetry_install_failed, "Unexpected error: #{inspect(e)}"}
        end
    end
  end

  defp install_poetry do
    # Install Poetry using the recommended method
    case System.cmd("python3", ["-c", "import requests; exec(requests.get('https://install.python-poetry.org').text)"], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("#{color("✓", :green)} Poetry installed successfully")
        IO.puts(output)
        # Add Poetry to PATH for the current process
        path = System.get_env("HOME") <> "/.local/bin:" <> System.get_env("PATH")
        System.put_env("PATH", path)
        :ok
      {error, _} ->
        {:error, :poetry_install_failed, error}
    end
  end

  defp setup_python_environment do
    IO.puts("\nSetting up Python environment with Poetry...")
    python_project_path = Path.join(File.cwd!(), "apps/axon_python")

    # Remove the existing virtual environment and poetry.lock file if they exist
    File.rm_rf!(Path.join([python_project_path, ".venv"]))
    File.rm(Path.join([python_project_path, "poetry.lock"]))

    # Use the current python3 interpreter for the Poetry environment
    case System.cmd("poetry", ["env", "use", "python3"],
           cd: python_project_path,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        # Install dependencies without installing the root project
        case System.cmd("poetry", ["install", "--no-root"],
             cd: python_project_path,
             stderr_to_stdout: true
           ) do
          {_, 0} ->
            IO.puts("#{color("✓", :green)} Python environment set up with Poetry")
            :ok
          {error, _} ->
            {:error, :dependency_install_failed, "Failed to install Python dependencies: #{error}"}
        end
        |> install_grpc_dependencies()
      {error, _} ->
        {:error, :venv_creation_failed, "Failed to set up virtual environment: #{error}"}
    end
  end

  def install_grpc_dependencies(:ok) do
    IO.puts("\nInstalling grpcio, protobuf, and grpcio-tools...")
    python_project_path = Path.join(File.cwd!(), "apps/axon_python")

    case System.cmd("poetry", ["add", "grpcio", "protobuf", "grpcio-tools"],
         cd: python_project_path,
         stderr_to_stdout: true) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} grpcio, protobuf, and grpcio-tools installed")
        :ok
      {error, _} ->
        {:error, :dependency_install_failed, "Failed to install grpcio, protobuf, and grpcio-tools: #{error}"}
    end
  end

  def install_grpc_dependencies(:error, error) do
    {:error, :venv_creation_failed, "Failed to set up virtual environment using Poetry: #{error}"}
  end

  defp fetch_elixir_deps do
    IO.puts("\nFetching Elixir dependencies...")
    case System.cmd("mix", ["deps.get"]) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} Dependencies fetched")
        :ok
      {error, _} ->
        {:error, :deps_fetch, "Failed to fetch dependencies: #{error}"}
    end
  end

  defp compile_project do
    IO.puts("\nCompiling project...")
    case System.cmd("mix", ["compile"]) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} Project compiled")
        :ok
      {error, _} ->
        {:error, :compile, "Failed to compile project: #{error}"}
    end
  end


  defp print_error(%Axon.Setup.Error{} = error) do
    IO.puts("""

    #{color("╔══ Error ══╗", :red)}
    #{error.message}

    #{color("Context:", :yellow)}
    #{format_context(error.context)}

    #{color("Need help?", :blue)}
    - Check the error message and context above
    - Ensure all system requirements are met
    - Try running the commands manually
    - Check the documentation at docs/setup.md
    """)
  end

  defp print_error(error) do
    IO.puts("\n#{color("✗ Error:", :red)} #{Exception.message(error)}")
  end

  defp format_context(context) when context == %{}, do: "  No additional context"
  defp format_context(context) do
    context
    |> Enum.map(fn {key, value} -> "  #{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end

  defp color(text, color_name) do
    "#{@colors[color_name]}#{text}#{@colors[:reset]}"
  end
end

Axon.Setup.run()
