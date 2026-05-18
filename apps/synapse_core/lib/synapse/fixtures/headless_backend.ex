defmodule Synapse.Fixtures.HeadlessBackend do
  @moduledoc """
  Deterministic AppKit HeadlessSurface backend for fixture-backed run controls.
  """

  alias AppKit.Core.RuntimeReadback.CommandResult

  def runtime_run_detail(_context, run_ref, _request, _opts) do
    {:ok, Synapse.AgentRuns.fixture_detail(run_ref)}
  end

  def request_runtime_refresh(_context, request, _opts) do
    command_result(:refresh, request.idempotency_key, request.scope_ref, request.actor_ref)
  end

  def request_runtime_control(_context, request, _opts) do
    command_result(
      request.action,
      request.idempotency_key,
      request.run_ref || request.subject_ref,
      request.actor_ref
    )
  end

  def state_snapshot(_context, _request, _opts), do: {:ok, %{rows: Synapse.AgentRuns.list_runs()}}

  def runtime_subject_detail(_context, subject_ref, _request, _opts),
    do: {:ok, %{subject_ref: subject_ref}}

  defp command_result(kind, idempotency_key, scope_ref, actor_ref) do
    token = scope_ref |> to_string() |> String.split("/", trim: true) |> List.last()

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
end
