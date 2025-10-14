defmodule SynapseCore.ErrorTest do
  use ExUnit.Case
  alias SynapseCore.Error
  alias SynapseCore.Error.{PythonEnvError, AgentError, HTTPError, ToolError}
  
  describe "error creation" do
    test "creates PythonEnvError with context" do
      error = PythonEnvError.new(:version_mismatch, %{
        found: "3.8.0",
        required: "3.10.0"
      })

      assert error.reason == :version_mismatch
      assert error.context.found == "3.8.0"
      assert error.context.required == "3.10.0"
      assert error.message =~ "Python version mismatch"
    end

    test "creates AgentError with context" do
      error = AgentError.new(:execution_failed, %{
        error: "Memory limit exceeded"
      })

      assert error.reason == :execution_failed
      assert error.context.error == "Memory limit exceeded"
      assert error.message =~ "Agent execution failed"
    end

    test "creates HTTPError with context" do
      error = HTTPError.new(:connection_failed, %{
        error: "Connection refused"
      })

      assert error.reason == :connection_failed
      assert error.context.error == "Connection refused"
      assert error.message =~ "Failed to connect"
    end

    test "creates ToolError with context" do
      error = ToolError.new(:validation_failed, %{
        error: "Missing required parameter"
      })

      assert error.reason == :validation_failed
      assert error.context.error == "Missing required parameter"
      assert error.message =~ "Tool parameter validation failed"
    end
  end

  describe "error formatting" do
    setup do
      error = PythonEnvError.new(:version_mismatch, %{
        found: "3.8.0",
        required: "3.10.0"
      })

      {:ok, error: error}
    end

    test "formats error with default options", %{error: error} do
      formatted = Error.format_error(error)
      
      assert formatted =~ "=== PythonEnvError ==="
      assert formatted =~ "Message: Python version mismatch"
      assert formatted =~ "Reason: :version_mismatch"
      assert formatted =~ "Context:"
      assert formatted =~ "found: \"3.8.0\""
      assert formatted =~ "required: \"3.10.0\""
    end

    test "includes stacktrace when requested", %{error: error} do
      formatted = Error.format_error(error, include_stacktrace: true)
      
      assert formatted =~ "Stacktrace:"
      assert formatted =~ "test/synapse_core/error_test.exs"
    end

    test "formats without color when disabled", %{error: error} do
      formatted = Error.format_error(error, color: false)
      
      refute formatted =~ "\e[31m" # red
      refute formatted =~ "\e[32m" # green
      refute formatted =~ "\e[0m"  # reset
    end

    test "formats without timestamp when disabled", %{error: error} do
      formatted = Error.format_error(error, timestamp: false)
      
      refute formatted =~ ~r/\[\d{4}-\d{2}-\d{2}/
    end
  end

  describe "error logging" do
    import ExUnit.CaptureLog
    
    test "logs error with proper severity" do
      error = PythonEnvError.new(:python_not_found)

      log = capture_log(fn ->
        Error.log_error(error, severity: :error)
      end)

      assert log =~ "[error]"
      assert log =~ "Python interpreter not found"
    end

    test "logs with different severity levels" do
      error = PythonEnvError.new(:python_not_found)

      debug_log = capture_log(fn ->
        Error.log_error(error, severity: :debug)
      end)

      info_log = capture_log(fn ->
        Error.log_error(error, severity: :info)
      end)

      warn_log = capture_log(fn ->
        Error.log_error(error, severity: :warn)
      end)

      assert debug_log =~ "[debug]"
      assert info_log =~ "[info]"
      assert warn_log =~ "[warn]"
    end
  end

  describe "error recovery" do
    test "raises when used in with statement" do
      result = with :ok <- create_error() do
        :ok
      end

      assert {:error, %PythonEnvError{}} = result
    end

    test "can be rescued" do
      result = try do
        raise PythonEnvError.new(:python_not_found)
      rescue
        e in PythonEnvError -> {:error, e}
      end

      assert {:error, %PythonEnvError{}} = result
    end
  end

  # Helper Functions

  defp create_error do
    {:error, PythonEnvError.new(:python_not_found)}
  end
end
