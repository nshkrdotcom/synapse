#!/usr/bin/env elixir

Mix.start()
Mix.shell(Mix.Shell.IO)

defmodule Axon.Setup.Error do
  defexception [:message, :reason, :context]
  
  def new(reason, context \\ %{}) do
    message = case reason do
      :python_not_found ->
        "Python interpreter not found. Please ensure Python 3.10 or higher is installed."
      :version_mismatch ->
        "Python version mismatch. Found: #{context[:found]}, Required: #{context[:required]}"
      :venv_creation_failed ->
        "Failed to create virtual environment: #{context[:error]}"
      :dependency_install_failed ->
        "Failed to install dependencies: #{context[:error]}"
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
         :ok <- check_python_version(),
         :ok <- fetch_elixir_deps(),
         :ok <- compile_project() do
      
      IO.puts("""
      \n#{color("✓ Setup completed successfully!", :green)}
      
      Run 'iex -S mix' to start the application.
      """)
    else
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
      {:error, "Elixir version must be >= #{min_version} (found: #{version})"}
    end
  end

  defp check_python_version do
    IO.puts("\nChecking Python installation...")
    
    case System.cmd("python3", ["--version"]) do
      {version, 0} ->
        version = version |> String.trim() |> String.split(" ") |> List.last()
        min_version = "3.10.0"

        if Version.match?(version, ">= #{min_version}") do
          IO.puts("#{color("✓", :green)} Python version #{version} OK")
          check_venv_module()
        else
          {:error, Axon.Setup.Error.new(:version_mismatch, %{
            found: version,
            required: min_version
          })}
        end
      {_, _} ->
        {:error, Axon.Setup.Error.new(:python_not_found)}
    end
  end

  defp check_venv_module do
    case System.cmd("python3", ["-c", "import venv"]) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} Python venv module OK")
        :ok
      {_, _} ->
        IO.puts("\nℹ️  Installing Python venv module...")
        case System.cmd("sudo", ["apt-get", "update"]) do
          {_, 0} ->
            case System.cmd("sudo", ["apt-get", "install", "-y", "python3-venv"]) do
              {_, 0} -> 
                IO.puts("#{color("✓", :green)} Python venv module installed")
                :ok
              {error, _} ->
                {:error, Axon.Setup.Error.new(:dependency_install_failed, %{
                  error: error,
                  package: "python3-venv"
                })}
            end
          {error, _} ->
            {:error, Axon.Setup.Error.new(:dependency_install_failed, %{
              error: error,
              command: "apt-get update"
            })}
        end
    end
  end

  defp fetch_elixir_deps do
    IO.puts("\nFetching Elixir dependencies...")
    case System.cmd("mix", ["deps.get"]) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} Dependencies fetched")
        :ok
      {error, _} ->
        {:error, Axon.Setup.Error.new(:dependency_install_failed, %{
          error: error,
          command: "mix deps.get"
        })}
    end
  end

  defp compile_project do
    IO.puts("\nCompiling project...")
    case System.cmd("mix", ["compile"]) do
      {_, 0} ->
        IO.puts("#{color("✓", :green)} Project compiled")
        :ok
      {error, _} ->
        {:error, Axon.Setup.Error.new(:dependency_install_failed, %{
          error: error,
          command: "mix compile"
        })}
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
