defmodule AxonCore.Error do
  @moduledoc """
  Error handling for AxonCore.
  """

  defmodule PythonEnvError do
    @moduledoc """
    Error raised when there are issues with the Python environment.
    """
    defexception [:message, :context]

    @impl true
    def exception(msg) when is_binary(msg), do: %__MODULE__{message: msg, context: %{}}
    def exception({msg, context}), do: %__MODULE__{message: msg, context: context}

    def new(msg, context \\ %{})
    def new(:python_not_found, _context) do
      %__MODULE__{
        message: "Python interpreter not found. Please ensure Python 3.10 or higher is installed.",
        context: %{}
      }
    end

    def new(:version_mismatch, %{found: found, required: required}) do
      %__MODULE__{
        message: "Python version mismatch. Found: #{found}, Required: #{required}",
        context: %{found: found, required: required}
      }
    end

    def new(:venv_package_missing, %{error: error, install_cmd: cmd}) do
      %__MODULE__{
        message: """
        Python venv package is not installed. Please install it using:

            #{cmd}

        You may need to use sudo with that command.
        """,
        context: %{error: error, install_cmd: cmd}
      }
    end

    def new(:venv_creation_failed, %{error: error}) do
      %__MODULE__{
        message: "Failed to create Python virtual environment: #{error}",
        context: %{error: error}
      }
    end

    def new(:pip_upgrade_failed, %{error: error}) do
      %__MODULE__{
        message: "Failed to upgrade pip: #{error}",
        context: %{error: error}
      }
    end

    def new(:poetry_install_failed, %{error: error}) do
      %__MODULE__{
        message: "Failed to install Poetry: #{error}",
        context: %{error: error}
      }
    end

    def new(:dependency_install_failed, %{error: error}) do
      %__MODULE__{
        message: "Failed to install Python dependencies: #{error}",
        context: %{error: error}
      }
    end

    def new(:project_structure_failed, %{error: error}) do
      %__MODULE__{
        message: "Failed to create project structure: #{error}",
        context: %{error: error}
      }
    end

    def new(msg, context) when is_atom(msg) do
      %__MODULE__{message: to_string(msg), context: context}
    end

    def new(msg, context) do
      %__MODULE__{message: msg, context: context}
    end
  end

  @doc """
  Log an error with its context.
  """
  def log_error(%{message: message, context: context} = error) do
    require Logger
    Logger.error("#{message}\nContext: #{inspect(context, pretty: true)}")
    error
  end
end
