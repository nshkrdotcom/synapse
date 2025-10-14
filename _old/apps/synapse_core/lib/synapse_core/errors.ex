defmodule SynapseCore.Error do
  @moduledoc """
  Standardized error handling for Synapse.
  Provides structured error types and helpful debug information.
  """

  require Logger
  
  @type severity :: :debug | :info | :warn | :error
  @type format_opts :: [include_stacktrace: boolean(), color: boolean(), timestamp: boolean()]

  # ANSI color codes
  @colors %{
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    reset: "\e[0m"
  }

  defmodule PythonEnvError do
    @moduledoc "Errors related to Python environment setup and management"
    defexception [:message, :reason, :context]

    @type t :: %__MODULE__{
      message: String.t(),
      reason: atom(),
      context: map()
    }

    def new(reason, context \\ %{}) do
      message = case reason do
        :python_not_found ->
          "Python interpreter not found. Please ensure Python #{SynapseCore.PythonEnvManager.min_version()} or higher is installed."
        :version_mismatch ->
          "Python version mismatch. Found: #{context[:found]}, Required: #{context[:required]}"
        :venv_creation_failed ->
          "Failed to create virtual environment: #{context[:error]}"
        :pip_upgrade_failed ->
          "Failed to upgrade pip: #{context[:error]}"
        :poetry_install_failed ->
          "Failed to install poetry: #{context[:error]}"
        :dependency_install_failed ->
          "Failed to install dependencies: #{context[:error]}"
        _ ->
          "Unknown Python environment error: #{inspect(reason)}"
      end

      %__MODULE__{
        message: message,
        reason: reason,
        context: context
      }
    end

    def message(%__MODULE__{message: message}), do: message
  end

  defmodule AgentError do
    @moduledoc "Errors related to agent lifecycle and execution"
    defexception [:message, :reason, :context]

    @type t :: %__MODULE__{
      message: String.t(),
      reason: atom(),
      context: map()
    }

    def new(reason, context \\ %{}) do
      message = case reason do
        :start_failed ->
          "Failed to start agent: #{context[:error]}"
        :not_found ->
          "Agent '#{context[:name]}' not found"
        :already_exists ->
          "Agent '#{context[:name]}' already exists"
        :execution_failed ->
          "Agent execution failed: #{context[:error]}"
        :timeout ->
          "Agent operation timed out after #{context[:timeout]}ms"
        _ ->
          "Unknown agent error: #{inspect(reason)}"
      end

      %__MODULE__{
        message: message,
        reason: reason,
        context: context
      }
    end

    def message(%__MODULE__{message: message}), do: message
  end

  defmodule HTTPError do
    @moduledoc "Errors related to HTTP communication"
    defexception [:message, :reason, :context]

    @type t :: %__MODULE__{
      message: String.t(),
      reason: atom(),
      context: map()
    }

    def new(reason, context \\ %{}) do
      message = case reason do
        :connection_failed ->
          "Failed to connect to Python service: #{context[:error]}"
        :invalid_response ->
          "Invalid response from Python service: #{context[:error]}"
        :timeout ->
          "HTTP request timed out after #{context[:timeout]}ms"
        :stream_error ->
          "Stream error: #{context[:error]}"
        _ ->
          "Unknown HTTP error: #{inspect(reason)}"
      end

      %__MODULE__{
        message: message,
        reason: reason,
        context: context
      }
    end

    def message(%__MODULE__{message: message}), do: message
  end

  defmodule ToolError do
    @moduledoc "Errors related to tool registration and execution"
    defexception [:message, :reason, :context]

    @type t :: %__MODULE__{
      message: String.t(),
      reason: atom(),
      context: map()
    }

    def new(reason, context \\ %{}) do
      message = case reason do
        :invalid_schema ->
          "Invalid tool schema: #{context[:error]}"
        :registration_failed ->
          "Tool registration failed: #{context[:error]}"
        :execution_failed ->
          "Tool execution failed: #{context[:error]}"
        :not_found ->
          "Tool '#{context[:name]}' not found"
        :validation_failed ->
          "Tool parameter validation failed: #{context[:error]}"
        _ ->
          "Unknown tool error: #{inspect(reason)}"
      end

      %__MODULE__{
        message: message,
        reason: reason,
        context: context
      }
    end

    def message(%__MODULE__{message: message}), do: message
  end

  @doc """
  Helper to format error messages with context for logging.
  
  Options:
  - include_stacktrace: boolean(), defaults to false
  - color: boolean(), defaults to true
  - timestamp: boolean(), defaults to true
  """
  def format_error(error, opts \\ []) do
    include_stacktrace = Keyword.get(opts, :include_stacktrace, false)
    use_color = Keyword.get(opts, :color, true)
    include_timestamp = Keyword.get(opts, :timestamp, true)
    
    error_type = error.__struct__ |> Module.split() |> List.last()
    timestamp = if include_timestamp, do: format_timestamp(), else: ""
    
    header = color("=== #{error_type} ===", :red, use_color)
    message = color("Message: #{error.message}", :yellow, use_color)
    reason = color("Reason: #{inspect(error.reason)}", :magenta, use_color)
    context = format_context(error.context, use_color)
    
    parts = [
      timestamp,
      header,
      message,
      reason,
      "Context:",
      context
    ]

    if include_stacktrace do
      stacktrace = format_stacktrace(Process.info(self(), :current_stacktrace), use_color)
      parts ++ ["Stacktrace:", stacktrace]
    else
      parts
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  Helper to log errors with proper severity and formatting.
  
  Options:
  - severity: :debug | :info | :warn | :error, defaults to :error
  - include_stacktrace: boolean(), defaults to false
  - color: boolean(), defaults to true
  - timestamp: boolean(), defaults to true
  """
  def log_error(error, opts \\ []) do
    severity = Keyword.get(opts, :severity, :error)
    formatted = format_error(error, opts)
    
    case severity do
      :debug -> Logger.debug(formatted)
      :info -> Logger.info(formatted)
      :warn -> Logger.warn(formatted)
      :error -> Logger.error(formatted)
      level when is_atom(level) -> Logger.log(level, formatted)
    end

    error
  end

  # Private Functions

  defp format_timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    color("[#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(minute)}:#{pad(second)}]", :cyan, true)
  end

  defp pad(num) when num < 10, do: "0#{num}"
  defp pad(num), do: "#{num}"

  defp format_context(context, use_color) when is_map(context) do
    context
    |> Enum.map(fn {key, value} ->
      "  #{color(to_string(key), :green, use_color)}: #{inspect(value)}"
    end)
    |> Enum.join("\n")
  end

  defp format_stacktrace({:current_stacktrace, stacktrace}, use_color) do
    stacktrace
    |> Enum.map(fn {mod, fun, arity, location} ->
      location_str = case location do
        [] -> ""
        loc -> " (#{inspect(loc)})"
      end
      
      "  #{color("#{inspect(mod)}.#{fun}/#{arity}", :blue, use_color)}#{location_str}"
    end)
    |> Enum.join("\n")
  end

  defp color(text, color_name, true) do
    "#{@colors[color_name]}#{text}#{@colors[:reset]}"
  end
  defp color(text, _color_name, false), do: text
end
