defmodule Synapse.TurnsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.Turns

  defmodule ExplicitRuntimeBackend do
    def start_agent_run(_context, request, _opts) do
      RunOutcomeFuture.new(%{
        run_ref: "run://live-stack/#{request.submission_dedupe_key}",
        accepted?: true,
        command_ref: "command://live-stack/start/#{request.submission_dedupe_key}",
        correlation_id: request.correlation_id
      })
    end

    def submit_agent_turn(_context, submission, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:submit_agent_turn, submission, opts})

      CommandResult.new(%{
        command_ref: "command://live-stack/turn/#{submission.idempotency_key}",
        command_kind: :submit_turn,
        accepted?: true,
        coalesced?: false,
        status: :accepted,
        authority_state: :local_policy,
        authority_refs: [],
        workflow_effect_state: "pending_signal",
        projection_state: :pending,
        correlation_id: submission.run_ref,
        receipt_ref: "receipt://live-stack/turn",
        idempotency_key: submission.idempotency_key,
        message: "turn accepted"
      })
    end

    def cancel_agent_run(_context, _run_ref, _opts), do: {:error, :not_used}
    def await_agent_outcome(_context, _run_ref, _request, _opts), do: {:error, :not_used}
  end

  test "submits a fixture-backed turn through AgentIntake DTOs" do
    assert {:ok, result} =
             Turns.submit_turn("phase-3", %{
               "kind" => "user_input",
               "input_summary" => "Continue"
             })

    assert %CommandResult{} = result
    assert result.command_kind == :submit_turn
    assert result.accepted? == true
  end

  test "submits a turn through explicitly supplied live-stack runtime options" do
    assert {:ok, result} =
             Turns.submit_turn(
               "run://live-stack/explicit-live-stack",
               %{"kind" => "user_input", "input_summary" => "Continue live stack proof"},
               backend: ExplicitRuntimeBackend,
               runtime_adapter: ExplicitRuntimeBackend,
               runtime_binding: %{runtime_binding_ref: "runtime-binding://test/agent-loop"},
               test_pid: self()
             )

    assert %CommandResult{} = result
    assert result.command_kind == :submit_turn
    assert result.receipt_ref == "receipt://live-stack/turn"

    assert_received {:submit_agent_turn, submission, opts}
    assert submission.run_ref == "run://live-stack/explicit-live-stack"
    assert submission.kind == :user_input
    assert Keyword.fetch!(opts, :runtime_adapter) == ExplicitRuntimeBackend
  end

  test "rejects unknown turn kinds without creating atoms" do
    assert {:error, :invalid_turn_kind} =
             Turns.submit_turn("phase-3", %{"kind" => "unknown_turn_kind"})
  end
end
