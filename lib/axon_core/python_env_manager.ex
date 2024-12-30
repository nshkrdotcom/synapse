defmodule AxonCore.PythonEnvManager do
  @moduledoc """
  Manages Python virtual environments for Axon agents.
  Handles creation, activation, and cleanup of venvs.
  Assumes Python venv module is available (installed during project setup).
  """

  require Logger

  alias AxonCore.PythonEnvManager

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
         :ok <- copy_python_sources(),
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
    # Get application priv dir - this will be created during compilation
    priv_dir = :code.priv_dir(:axon_core)
    python_root = Path.join(priv_dir, "python")
    src_path = python_package_path()
    agents_path = Path.join(src_path, "agents")

    Logger.info("Ensuring project structure:")
    Logger.info("  priv_dir: #{inspect(priv_dir)}")
    Logger.info("  python_root: #{python_root}")
    Logger.info("  src_path: #{src_path}")
    Logger.info("  agents_path: #{agents_path}")

    # Create all directories
    with :ok <- ensure_directory(python_root),
         :ok <- ensure_directory(src_path),
         :ok <- ensure_directory(agents_path) do
      Logger.info("Successfully created all directories")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to create directory structure: #{inspect(reason)}")
        {:error, :project_structure_failed, %{error: reason}}
    end
  end

  defp ensure_directory(path) do
    Logger.info("Ensuring directory exists: #{path}")
    case File.mkdir_p(path) do
      :ok ->
        Logger.info("Directory exists or was created: #{path}")
        :ok
      {:error, reason} = error ->
        Logger.error("Failed to create directory #{path}: #{inspect(reason)}")
        error
    end
  end

  defp ensure_directory(path) do
    Logger.info("Ensuring directory exists: #{path}")
    if File.exists?(path) do
      if File.dir?(path) do
        Logger.info("Directory already exists: #{path}")
        :ok
      else
        Logger.error("Path exists but is not a directory: #{path}")
        {:error, {:not_directory, path}}
      end
    else
      Logger.info("Creating directory: #{path}")
      case File.mkdir_p(path) do
        :ok ->
          Logger.info("Successfully created directory: #{path}")
          :ok
        {:error, reason} = error ->
          Logger.error("Failed to create directory #{path}: #{inspect(reason)}")
          error
      end
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
    # Use the same path resolution as our other functions
    #source_root = source_root()
    python_package_dir = project_root()
    venv_python = python_path()
    #project_root = File.cwd!()


    Logger.info("Installing dependencies in: #{python_package_dir}")
    Logger.info("Using Python from: #{venv_python}")

    # First install Poetry
    case System.cmd(venv_python, ["-m", "pip", "install", "poetry"],
           env: env_vars(),
           cd: python_package_dir,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Logger.info("Successfully installed Poetry: #{output}")
        venv_poetry = Path.join([venv_path(), "bin", "poetry"])
        Logger.info("Poetry binary at: #{venv_poetry}")

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

  defp copy_python_sources do
    source_root = source_root()
    project_root = project_root()

    Logger.info("Copying Python sources from #{source_root} to #{project_root}")
    python_src_path = Path.join(source_root, "src")
    python_dest_path = Path.join(project_root, "src")

    # Ensure the destination directory exists, removing the old one if necessary
    if File.exists?(python_dest_path) do
      Logger.info("Removing existing Python destination path #{python_dest_path}...")
      File.rm_rf!(python_dest_path)
    end
    # File.mkdir_p!(python_dest_path) # No longer needed since File.cp_r! creates the directory

    # Copy the Python source directory
    try do
      File.cp_r!(python_src_path, python_dest_path)
    catch
      # Catch any errors during the copying process
      e ->
        Logger.error("Failed to copy Python sources: #{inspect(e)}")
        {:error, :python_source_copy_failed, %{reason: e}}
    end

    # Copy pyproject.toml
    Logger.info("Copying pyproject.toml from #{source_root} to #{project_root}")
    try do
      File.cp!(Path.join(source_root, "pyproject.toml"), Path.join(project_root, "pyproject.toml"))
    catch
      e ->
        Logger.error("Failed to copy pyproject.toml: #{inspect(e)}")
        {:error, :pyproject_copy_failed, %{reason: e}}
    end

    # Remove poetry.lock if it exists in the destination
    if File.exists?(Path.join(project_root, "poetry.lock")) do
      Logger.info("Removing existing poetry.lock at #{project_root}")
      File.rm!(Path.join(project_root, "poetry.lock"))
    end

    # If we reached this point, everything was successful
    :ok
  end

  # defp project_root do
  #   Application.app_dir(:axon_core, "priv/python")
  # end

  defp project_root do
    # Use :code.priv_dir to get the correct priv directory path
    priv_dir = :code.priv_dir(:axon_core)
    Path.join(priv_dir, "python")
  end

  # defp lib_root do
  #   # Use :code.priv_dir to get the correct priv directory path
  #   priv_dir = :code.lib_dir(:axon_core)
  # end

  defp source_root do
    # Use :code.priv_dir to get the correct priv directory path
    Path.join(File.cwd!(), "script")
  end

  defp python_package_path do
    Path.join([project_root(), "src"])
  end
end
