defmodule AxonCore.PythonEnvManager do
  @moduledoc """
  Manages Python virtual environments for Axon agents.
  Handles creation, activation, and cleanup of venvs.
  """
  
  require Logger
  alias AxonCore.Error.PythonEnvError

  @venv_dir ".venv"
  @requirements_file "pyproject.toml"
  @python_min_version "3.10"

  def min_version, do: @python_min_version

  @doc """
  Ensures a Python environment is ready for use.
  Creates and configures if needed.
  """
  def ensure_env! do
    with :ok <- check_python_version(),
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

  # Private Functions

  defp check_python_version do
    case System.cmd("python3", ["--version"]) do
      {version, 0} ->
        version = version |> String.trim() |> String.split(" ") |> List.last()
        if Version.match?(version, ">= #{@python_min_version}") do
          :ok
        else
          {:error, :version_mismatch, %{found: version, required: @python_min_version}}
        end
      {_, _} ->
        {:error, :python_not_found, %{}}
    end
  end

  defp ensure_venv do
    if File.exists?(venv_path()) do
      :ok
    else
      Logger.info("Creating Python virtual environment...")
      case System.cmd("python3", ["-m", "venv", venv_path()]) do
        {_, 0} -> :ok
        {error, _} -> {:error, :venv_creation_failed, %{error: error}}
      end
    end
  end

  defp install_dependencies do
    Logger.info("Installing Python dependencies...")
    
    # First, ensure pip is up to date
    with :ok <- upgrade_pip(),
         :ok <- install_poetry(),
         :ok <- install_project_deps() do
      :ok
    end
  end

  defp upgrade_pip do
    case System.cmd(python_path(), ["-m", "pip", "install", "--upgrade", "pip"],
           env: env_vars(),
           cd: project_root()
         ) do
      {_, 0} -> :ok
      {error, _} -> {:error, :pip_upgrade_failed, %{error: error}}
    end
  end

  defp install_poetry do
    case System.cmd(python_path(), ["-m", "pip", "install", "poetry"],
           env: env_vars(),
           cd: project_root()
         ) do
      {_, 0} -> :ok
      {error, _} -> {:error, :poetry_install_failed, %{error: error}}
    end
  end

  defp install_project_deps do
    case System.cmd(Path.join([venv_path(), "bin", "poetry"]), ["install"],
           env: env_vars(),
           cd: project_root()
         ) do
      {_, 0} -> :ok
      {error, _} -> {:error, :dependency_install_failed, %{error: error}}
    end
  end

  defp venv_path do
    Path.join(project_root(), @venv_dir)
  end

  defp project_root do
    Application.app_dir(:axon_core, "priv/python")
  end

  defp python_package_path do
    Path.join([project_root(), "src"])
  end
end
