defmodule Synapse.Actions.GenerateCritiqueCompensationTest do
  use Synapse.SupertesterCase, async: false
  import ExUnit.CaptureLog

  alias Jido.Error
  alias Synapse.Actions.GenerateCritique

  describe "compensation on LLM failure" do
    test "executes compensation callback on server error" do
      params = %{
        prompt: "Test prompt",
        messages: [],
        profile: :test
      }

      error = Error.execution_error("Internal server error")

      # Test compensation directly
      logs =
        capture_log(fn ->
          assert {:ok, compensation_result} =
                   GenerateCritique.on_error(
                     params,
                     error,
                     %{request_id: "test_123"},
                     []
                   )

          assert compensation_result.compensated == true
          assert is_atom(compensation_result.original_error.type)
          assert %DateTime{} = compensation_result.compensated_at
        end)

      assert logs =~ "Compensating for LLM failure"
      assert logs =~ "test_123"
    end

    test "compensation includes error context" do
      params = %{prompt: "test", profile: :test}

      error = Error.execution_error("429 rate limit")

      capture_log(fn ->
        {:ok, result} = GenerateCritique.on_error(params, error, %{}, [])

        assert result.original_error.message =~ "rate limit" or
                 result.original_error.message =~ "429"
      end)
    end

    test "compensation logs profile information for debugging" do
      params = %{prompt: "test", profile: :test}

      error = Error.execution_error("Unauthorized")

      logs =
        capture_log(fn ->
          {:ok, result} =
            GenerateCritique.on_error(params, error, %{request_id: "debug_test"}, [])

          # Verify the result contains profile information
          assert result.request_id == "debug_test"
        end)

      # Verify compensation logged
      assert logs =~ "Compensating for LLM failure"
      assert logs =~ "debug_test"
    end

    test "compensation includes request_id for tracking" do
      params = %{prompt: "test", profile: :test}

      error = Error.execution_error("Server error")

      capture_log(fn ->
        {:ok, result} = GenerateCritique.on_error(params, error, %{request_id: "req_abc123"}, [])

        assert result.request_id == "req_abc123"
      end)
    end
  end

  describe "compensation configuration" do
    test "action has compensation enabled" do
      # Verify compile-time configuration via metadata
      metadata = GenerateCritique.__action_metadata__()
      assert metadata.compensation[:enabled] == true
      assert metadata.compensation[:max_retries] >= 1
    end

    test "compensation callback is defined" do
      assert Code.ensure_loaded?(GenerateCritique)
      assert function_exported?(GenerateCritique, :on_error, 4)
    end
  end

  describe "telemetry emission" do
    test "emits telemetry event on compensation" do
      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-compensation-handler",
        [:synapse, :llm, :compensation],
        fn _event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-compensation-handler") end)

      params = %{prompt: "test", profile: :test}
      error = Error.execution_error("simulated failure")

      capture_log(fn ->
        {:ok, _result} =
          GenerateCritique.on_error(params, error, %{request_id: "telemetry_test"}, [])

        # Verify telemetry event was emitted
        assert_receive {:telemetry_event, measurements, metadata}, 1000

        assert measurements.system_time != nil
        assert metadata.request_id == "telemetry_test"
        assert metadata.profile == :test
        # Error type is now an atom based on the exception module
        assert is_atom(metadata.error_type)
      end)

      # Cleanup
      :telemetry.detach("test-compensation-handler")
    end
  end
end
