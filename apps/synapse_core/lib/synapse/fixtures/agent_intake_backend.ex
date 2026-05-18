defmodule Synapse.Fixtures.AgentIntakeBackend do
  @moduledoc """
  Deterministic AppKit AgentIntake backend for fixture-backed Synapse phases.
  """

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.{CommandResult, PollingState}

  def start_agent_run(_context, request, _opts) do
    token = request.submission_dedupe_key

    RunOutcomeFuture.new(%{
      run_ref: "run://fixture/#{token}",
      workflow_ref: "workflow://fixture/#{token}",
      accepted?: true,
      command_ref: "command://fixture/start/#{token}",
      correlation_id: request.correlation_id,
      polling_hint: polling_state("command://fixture/start/#{token}")
    })
  end

  def submit_agent_turn(_context, submission, _opts) do
    command_result(
      :submit_turn,
      submission.idempotency_key,
      submission.run_ref,
      submission.actor_ref
    )
  end

  def cancel_agent_run(_context, run_ref, _opts) when is_binary(run_ref) do
    command_result(:cancel, "fixture-cancel:#{run_ref}", run_ref, "actor:synapse:operator")
  end

  def await_agent_outcome(_context, run_ref, _request, _opts) when is_binary(run_ref) do
    {:ok,
     %{
       run_ref: run_ref,
       status: :fixture_backed,
       outcome_ref: "outcome://fixture/#{run_token(run_ref)}"
     }}
  end

  defp command_result(kind, idempotency_key, run_ref, actor_ref) do
    token = run_token(run_ref)

    CommandResult.new(%{
      command_ref: "command://fixture/#{kind}/#{token}",
      command_kind: kind,
      accepted?: true,
      coalesced?: false,
      status: :accepted,
      authority_state: :authorized,
      authority_refs: ["authority://fixture/operator"],
      workflow_effect_state: :applied,
      projection_state: :updated,
      correlation_id: "correlation://fixture/#{token}",
      receipt_ref: "receipt://fixture/#{kind}/#{token}",
      idempotency_key: idempotency_key,
      message: "Fixture #{kind} accepted for #{actor_ref}"
    })
  end

  defp polling_state(command_ref) do
    {:ok, polling_state} =
      PollingState.new(%{
        checking?: false,
        poll_interval_ms: 1_000,
        last_refresh_command_ref: command_ref,
        staleness_ms: 0
      })

    polling_state
  end

  defp run_token(run_ref) do
    run_ref
    |> String.split("/", trim: true)
    |> List.last()
  end
end
