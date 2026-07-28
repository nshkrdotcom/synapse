defmodule Synapse.Test.AppKitBackendStack do
  @moduledoc false

  def backend_stack do
    AppKit.BackendStack.new!(
      agent_intake_backend: Synapse.Test.AppKitBackend,
      headless_backend: Synapse.Test.AppKitBackend,
      effect_surface_backend: Synapse.Test.EffectBackend,
      review_backend: Synapse.Test.ReviewBackend
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
      "Conflict" ->
        surface_error("idempotency_conflict", "The request identity conflicts", :conflict, false)

      "Unavailable" ->
        surface_error("owner_unavailable", "The durable owner is unavailable", :transient, true)

      _title ->
        future(request.submission_dedupe_key, request.correlation_id)
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

defmodule Synapse.Test.EffectBackend do
  @moduledoc false

  @behaviour AppKit.EffectSurface

  @impl true
  def propose_effect(_context, _proposal, _opts), do: {:error, :effect_not_configured_for_test}

  @impl true
  def begin_dispatch(_context, _owner_execution_ref, _command, _opts),
    do: {:error, :effect_not_configured_for_test}

  @impl true
  def record_accepted(_context, _owner_execution_ref, _acceptance, _opts),
    do: {:error, :effect_not_configured_for_test}

  @impl true
  def record_receipt(_context, _owner_execution_ref, _receipt, _opts),
    do: {:error, :effect_not_configured_for_test}

  @impl true
  def get_effect(_context, _owner_execution_ref, _opts),
    do: {:error, :effect_not_configured_for_test}

  @impl true
  def get_effect_by_idempotency(_context, _idempotency_key, _opts),
    do: {:error, :effect_not_configured_for_test}
end

defmodule Synapse.Test.ReviewBackend do
  @moduledoc false

  @behaviour AppKit.Core.Backends.ReviewBackend

  alias AppKit.Core.{
    ActionResult,
    DecisionRef,
    DecisionSummary,
    PageResult,
    SubjectRef
  }

  @manifest_hash "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @content_digest "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  @impl true
  def list_pending(_context, _page_request, _opts) do
    with {:ok, primary} <- summary("review-unit-1", "Reviewed agent file effect", "pending"),
         {:ok, denied} <- summary("review-unit-denied", "Denied governed effect", "rejected") do
      PageResult.new(%{
        entries: [primary, denied],
        total_count: 2,
        has_more: false,
        metadata: %{source: :durable_test_backend}
      })
    end
  end

  @impl true
  def get_review(_context, %DecisionRef{id: "missing-review"}, _opts),
    do: {:error, :review_not_found}

  def get_review(_context, %DecisionRef{} = decision_ref, _opts) do
    {:ok,
     %{
       decision_ref: decision_ref,
       subject_ref: decision_ref.subject_ref || subject_ref!(),
       status: if(decision_ref.id == "review-unit-denied", do: "rejected", else: "pending"),
       summary: "Reviewed agent file effect",
       payload: %{
         "reviewer_actor" => %{"kind" => "human"},
         "reason_codes" => ["review_required", "exact_operation_required"],
         "evidence_refs" => ["receipt://test/review/#{decision_ref.id}"],
         "approval_payload" => approval_payload()
       }
     }}
  end

  @impl true
  def record_decision(context, %DecisionRef{} = decision_ref, attrs, opts),
    do: record_decision_by_id(context, decision_ref.id, attrs, opts)

  @impl true
  def record_decision_by_id(_context, decision_id, attrs, opts) do
    if pid = Keyword.get(opts, :test_pid) do
      send(pid, {:review_decision, decision_id, attrs})
    end

    ActionResult.new(%{
      status: :completed,
      action_ref: %{
        id: "#{decision_id}:#{map_value(attrs, :decision)}",
        action_kind: "review_#{map_value(attrs, :decision)}"
      },
      message: "Durable review decision recorded",
      metadata: %{
        decision_id: decision_id,
        decision: map_value(attrs, :decision),
        payload: map_value(attrs, :payload)
      }
    })
  end

  defp summary(id, title, status) do
    with {:ok, decision_ref} <-
           DecisionRef.new(%{
             id: id,
             decision_kind: "code_review",
             subject_ref: subject_ref!()
           }) do
      DecisionSummary.new(%{
        decision_ref: decision_ref,
        status: status,
        subject_ref: decision_ref.subject_ref,
        summary: title,
        payload: %{
          "reviewer_actor" => %{"kind" => "human"},
          "reason_codes" =>
            if(status == "rejected", do: ["authority_denied"], else: ["review_required"])
        }
      })
    end
  end

  defp subject_ref! do
    {:ok, subject_ref} =
      SubjectRef.new(%{id: "subject://test/reviewed-effect", subject_kind: "work_object"})

    subject_ref
  end

  defp approval_payload do
    %{
      "effect_ref" => "effect://test/reviewed-file",
      "pinned_tool_manifest" => %{
        "manifest_ref" => "manifest://test/codex",
        "manifest_hash" => @manifest_hash,
        "action_ids" => ["create_or_replace_one_named_text_file"]
      },
      "reviewed_operation" => %{
        "operation" => "create_or_replace",
        "workspace_ref" => "workspace://test/reviewed-effect",
        "file_ref" => "file://test/RESULT.txt",
        "relative_path" => "RESULT.txt",
        "content_digest" => @content_digest
      }
    }
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
