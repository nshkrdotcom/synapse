defmodule AxonCore.PythonEnvManager do
  @moduledoc """
  Manages Python virtual environments for Axon agents.
  Handles creation, activation, and cleanup of venvs.
  Assumes Python venv module is available (installed during project setup).
  """

  require Logger
  alias AxonCore.Error.PythonEnvError

  @python_min_version "3.10.0"

  def min_version, do: @python_min_version

  @doc """
  Ensures a Python environment is ready for use.
  Creates and configures if needed.
  """
  def ensure_env! do
    with :ok <- ensure_project_structure(),
         :ok <- check_python_version(),
         :ok <- ensure_venv(),
         :ok <- install_dependencies() do
      :ok
    else
      {:error, error} when is_exception(error) -> raise error
      {:error, reason, context} -> raise PythonEnvError.new(reason, context)
    end
  end

  @doc """
  Returns the path to the Python executable in the venv.
  """
  def python_path do
    Path.join([venv_path(), "bin", "python"])
  end

  @doc """
  Returns environment variables needed for Python execution.
  """
  def env_vars do
    [
      {"VIRTUAL_ENV", venv_path()},
      {"PATH", "#{Path.join(venv_path(), "bin")}:#{System.get_env("PATH")}"},
      {"PYTHONPATH", python_package_path()},
      {"PYTHONUNBUFFERED", "1"}
    ]
  end

  @doc """
  Returns the path to the Python virtual environment.
  """
  def venv_path do
    Path.join(project_root(), ".venv")
  end

  @doc """
  Returns virtualenv environment variables.
  """
  def get_venv_env do
    venv_path = venv_path()
    [
      {"VIRTUAL_ENV", venv_path},
      {"PATH", "#{venv_path}/bin:#{System.get_env("PATH")}"}
    ]
  end

  # Private Functions

  defp ensure_project_structure do
    python_root = project_root()
    src_path = python_package_path()
    agents_path = Path.join(src_path, "agents")

    with :ok <- File.mkdir_p(python_root),
         :ok <- File.mkdir_p(src_path),
         :ok <- File.mkdir_p(agents_path) do
      :ok
    else
      {:error, reason} -> {:error, :project_structure_failed, %{error: reason}}
    end
  end

  defp check_python_version do
    case System.cmd("python3", ["--version"]) do
      {version, 0} ->
        version = version |> String.trim() |> String.split(" ") |> List.last()
        # Clean up version string to ensure it's in proper semver format
        version =
          case String.split(version, ".") do
            [major, minor] -> "#{major}.#{minor}.0"
            [major, minor, patch | _] -> "#{major}.#{minor}.#{patch}"
            _ -> version
          end

        case Version.compare(version, @python_min_version) do
          :lt ->
            {:error, :version_mismatch, %{found: version, required: @python_min_version}}

          _ ->
            :ok
        end

      {_, _} ->
        {:error, :python_not_found, %{}}
    end
  rescue
    error -> {:error, :version_check_failed, %{error: inspect(error)}}
  end

  defp ensure_venv do
    venv = venv_path()
    Logger.info("Checking virtual environment at #{venv}...")

    # Always verify/fix the venv, even if it exists
    with :ok <- ensure_system_pip(),
         :ok <- setup_venv(venv),
         :ok <- verify_venv_pip() do
      :ok
    end
  end

  defp ensure_system_pip do
    case System.cmd("python3", ["-m", "pip", "--version"], stderr_to_stdout: true) do
      {version, 0} ->
        Logger.info("System pip found: #{version}")
        ensure_venv_package()

      {_error, _} ->
        Logger.info("System pip not found, installing via apt...")

        # If pip is not available, install it via apt
        case System.cmd("sudo", ["apt", "install", "-y", "python3-pip"],
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            Logger.info("Successfully installed python3-pip: #{output}")
            ensure_venv_package()

          {error, _} ->
            Logger.error("Failed to install python3-pip: #{error}")
            {:error, :pip_install_failed, %{error: error}}
        end
    end
  end

  defp ensure_venv_package do
    Logger.info("Ensuring python3-venv is installed...")

    case System.cmd("python3", ["--version"], stderr_to_stdout: true) do
      {version, 0} ->
        # Extract major.minor version (e.g., "3.12" from "Python 3.12.3")
        [major, minor | _] =
          version
          |> String.trim()
          |> String.split(" ")
          |> List.last()
          |> String.split(".")

        venv_package = "python#{major}.#{minor}-venv"
        Logger.info("Installing #{venv_package}...")

        case System.cmd("sudo", ["apt", "install", "-y", venv_package], stderr_to_stdout: true) do
          {output, 0} ->
            Logger.info("Successfully installed #{venv_package}: #{output}")
            :ok

          {error, _} ->
            Logger.error("Failed to install #{venv_package}: #{error}")
            {:error, :venv_install_failed, %{error: error}}
        end

      {error, _} ->
        Logger.error("Failed to get Python version: #{error}")
        {:error, :python_version_check_failed, %{error: error}}
    end
  end

  defp setup_venv(venv) do
    if File.exists?(venv) do
      Logger.info("Removing existing venv...")
      File.rm_rf!(venv)
    end

    Logger.info("Creating fresh venv...")

    case System.cmd("python3", ["-m", "venv", venv], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Successfully created venv: #{output}")
        :ok

      {error, _} ->
        Logger.error("Failed to create venv: #{error}")
        {:error, :venv_creation_failed, %{error: error}}
    end
  end

  defp verify_venv_pip do
    Logger.info("Verifying pip in venv...")
    venv_python = python_path()
    Logger.info("Using Python at: #{venv_python}")

    case System.cmd(venv_python, ["-m", "pip", "--version"],
           env: env_vars(),
           stderr_to_stdout: true
         ) do
      {version, 0} ->
        Logger.info("Venv pip found: #{version}")
        :ok

      {error, _} ->
        Logger.error("Pip not found in venv: #{error}")

        # Try to bootstrap pip in the venv
        Logger.info("Attempting to bootstrap pip in venv...")

        case System.cmd(venv_python, ["-m", "ensurepip", "--default-pip"],
               env: env_vars(),
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            Logger.info("Successfully bootstrapped pip: #{output}")
            :ok

          {error, _} ->
            Logger.error("Failed to bootstrap pip: #{error}")
            {:error, :venv_pip_failed, %{error: error}}
        end
    end
  end

  defp install_dependencies do
    Logger.info("Installing project dependencies...")
    python_package_dir = Path.join([File.cwd!(), "apps", "axon_core", "priv", "python"])
    venv_python = python_path()

    # First install Poetry
    case System.cmd(venv_python, ["-m", "pip", "install", "poetry"],
           env: env_vars(),
           cd: python_package_dir,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Logger.info("Successfully installed Poetry: #{output}")
        venv_poetry = Path.join([venv_path(), "bin", "poetry"])

        # Then use Poetry to install dependencies
        case System.cmd(venv_poetry, ["install", "--no-root"],
               env: env_vars(),
               cd: python_package_dir,
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            Logger.info("Successfully installed dependencies: #{output}")

            # Finally install the local package in development mode
            case System.cmd(venv_python, ["-m", "pip", "install", "-e", "."],
                   env: env_vars(),
                   cd: python_package_dir,
                   stderr_to_stdout: true
                 ) do
              {output, 0} ->
                Logger.info("Successfully installed local package: #{output}")
                :ok

              {error, _} ->
                Logger.error("Failed to install local package: #{error}")
                {:error, :local_package_install_failed, %{error: error}}
            end

          {error, _} ->
            Logger.error("Failed to install dependencies: #{error}")
            {:error, :dependency_install_failed, %{error: error}}
        end

      {error, _} ->
        Logger.error("Failed to install Poetry: #{error}")
        {:error, :poetry_install_failed, %{error: error}}
    end
  end

  defp project_root do
    Application.app_dir(:axon_core, "priv/python")
  end

  defp python_package_path do
    Path.join([project_root(), "src"])
  end
end
