defmodule Synapse.Test.AppKitBackendStack do
  @moduledoc false

  def backend_stack do
    AppKit.BackendStack.new!(
      agent_intake_backend: Synapse.Test.AppKitBackend,
      headless_backend: Synapse.Test.AppKitBackend
    )
  end
end

defmodule Synapse.Test.AppKitBackend do
  @moduledoc false

  alias AppKit.Core.AgentIntake.{
    AgentRunCursor,
    AgentRunEvent,
    AgentRunEventPage,
    RunOutcomeFuture
  }

  alias AppKit.Core.RuntimeReadback.{
    CommandResult,
    RuntimeRow,
    RuntimeRunDetail,
    RuntimeStateSnapshot
  }

  alias AppKit.Core.{PersistencePosture, SurfaceError}

  @timestamp "2026-07-20T00:00:00Z"

  def start_agent_run(_context, request, _opts) do
    case request.params.title do
      "Conflict" -> surface_error("idempotency_conflict", "The request identity conflicts", :conflict, false)
      "Unavailable" -> surface_error("owner_unavailable", "The durable owner is unavailable", :transient, true)
      _title -> future(request.submission_dedupe_key, request.correlation_id)
    end
  end

  def submit_agent_turn(_context, submission, _opts) do
    command_result(:submit_turn, submission.idempotency_key, submission.run_ref)
  end

  def cancel_agent_run(_context, run_ref, _opts) do
    command_result(:cancel, "cancel:#{run_ref}", run_ref)
  end

  def await_agent_outcome(_context, run_ref, _request, _opts) do
    future(run_token(run_ref), "correlation://synapse/readback")
  end

  def catch_up_agent_events(_context, cursor, _opts) do
    {:ok, advanced_cursor} =
      cursor
      |> Map.from_struct()
      |> Map.put(:cursor_ref, "cursor://test/#{run_token(cursor.ledger_ref)}/1")
      |> Map.put(:last_seq_seen, 1)
      |> AgentRunCursor.new()

    {:ok, event} =
      AgentRunEvent.new(%{
        event_ref: "event://test/#{run_token(cursor.ledger_ref)}/accepted",
        ledger_ref: cursor.ledger_ref,
        event_seq: 1,
        event_kind: :run_started,
        visibility: :product,
        observed_at: @timestamp,
        summary: "Run and initial turn accepted durably"
      })

    AgentRunEventPage.new(%{cursor: advanced_cursor, events: [event], has_more?: false})
  end

  def list_pending_interactions(_context, _request, _opts), do: {:ok, []}

  def state_snapshot(_context, _request, _opts) do
    {:ok, row} = runtime_row("run://durable/test-run")

    RuntimeStateSnapshot.new(%{
      tenant_ref: "tenant://default",
      installation_ref: "installation://default",
      generated_at: @timestamp,
      rows: [row],
      persistence_posture: PersistencePosture.durable(:runtime_projection)
    })
  end

  def runtime_run_detail(_context, run_ref, _request, _opts) do
    case run_ref do
      "unavailable" ->
        surface_error("owner_unavailable", "The durable owner is unavailable", :transient, true)

      "conflict" ->
        surface_error("read_conflict", "The run cursor conflicts", :conflict, false)

      _run_ref ->
        with {:ok, row} <- runtime_row(run_ref) do
          RuntimeRunDetail.new(%{
            run_ref: run_ref,
            runtime_row: row,
            turns: [%{turn_ref: "turn://durable/#{run_token(run_ref)}/1", sequence: 1}],
            persistence_posture: PersistencePosture.durable(:runtime_projection)
          })
        end
    end
  end

  def runtime_subject_detail(_context, _subject_ref, _request, _opts),
    do: {:error, :not_used}

  def request_runtime_refresh(_context, request, _opts),
    do: command_result(:refresh, request.idempotency_key, request.scope_ref)

  def request_runtime_control(_context, _request, _opts), do: {:error, :not_used}

  defp runtime_row(run_ref) do
    RuntimeRow.new(%{
      subject_ref: "subject://synapse/#{run_token(run_ref)}",
      run_ref: run_ref,
      workflow_ref: "workflow://durable/#{run_token(run_ref)}",
      state: :accepted,
      updated_at: @timestamp,
      persistence_posture: PersistencePosture.durable(:runtime_projection),
      extensions: %{
        title: "Durable run #{run_token(run_ref)}",
        goal_summary: "Read from the durable AppKit projection"
      }
    })
  end

  defp future(token, correlation_id) do
    RunOutcomeFuture.new(%{
      run_ref: "run://durable/#{token}",
      workflow_ref: "workflow://durable/#{token}",
      accepted?: true,
      command_ref: "command://durable/start/#{token}",
      correlation_id: correlation_id
    })
  end

  defp command_result(kind, idempotency_key, run_ref) do
    CommandResult.new(%{
      command_ref: "command://durable/#{kind}/#{run_token(run_ref)}",
      command_kind: kind,
      accepted?: true,
      coalesced?: false,
      status: :accepted,
      authority_state: :authorized,
      authority_refs: [],
      workflow_effect_state: :applied,
      projection_state: :updated,
      correlation_id: run_ref,
      idempotency_key: idempotency_key,
      message: "Accepted by durable test backend"
    })
  end

  defp surface_error(code, message, kind, retryable) do
    with {:ok, error} <-
           SurfaceError.new(%{
             code: code,
             message: message,
             kind: kind,
             retryable: retryable
           }) do
      {:error, error}
    end
  end

  defp run_token(run_ref), do: run_ref |> String.split("/", trim: true) |> List.last()
end
