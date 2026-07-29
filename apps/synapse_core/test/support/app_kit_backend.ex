defmodule Synapse.Test.AppKitBackendStack do
  @moduledoc false

  def backend_stack do
    AppKit.BackendStack.new!(
      agent_intake_backend: Synapse.Test.AppKitBackend,
      headless_backend: Synapse.Test.AppKitBackend,
      operator_backend: Synapse.Test.AppKitBackend,
      effect_surface_backend: Synapse.Test.EffectBackend,
      review_backend: Synapse.Test.ReviewBackend,
      product_surface_backend: Synapse.Test.ProductSurfaceBackend,
      runtime_backend: Synapse.Test.RuntimeBackend
    )
  end
end

defmodule Synapse.Test.ProductSurfaceBackend do
  @moduledoc false
  @behaviour AppKit.Core.Backends.ProductSurfaceBackend

  alias AppKit.Core.PersistencePosture

  @timestamp "2026-07-20T00:00:00Z"

  @impl true
  def run_projection(_context, "run://durable/unavailable-projection", _opts),
    do: {:error, :owner_unavailable}

  def run_projection(_context, run_ref, _opts) do
    {:ok,
     %{
       run_ref: run_ref,
       subject_ref: "subject://synapse/test-run",
       workflow_ref: "workflow://synapse/test-run",
       owner_projection_ref: "projection://mezzanine/run/test-run",
       source_contract_ref: "contract://mezzanine/run-acceptance/v1",
       state: :running,
       updated_at: @timestamp,
       cursor: cursor(run_ref),
       control: %{
         run_ref: run_ref,
         owner_projection_ref: "projection://mezzanine/control/test-run",
         source_contract_ref: "contract://mezzanine/recovery-control/v1",
         row_version: 3,
         state: :running,
         available_actions: [:pause, :cancel, :supersede],
         availability: :available
       },
       turns: [
         %{
           turn_ref: "turn://durable/test-run/1",
           run_ref: run_ref,
           owner_projection_ref: "projection://mezzanine/turn/test-run/1",
           source_contract_ref: "contract://mezzanine/agent-turn/v1",
           sequence: 1,
           state: :completed,
           input_ref: "artifact://synapse/turn/test-run/1/input",
           output_artifact_ref: "artifact://synapse/turn/test-run/1/output",
           event_refs: ["event://synapse/test-run/turn-completed"],
           artifact_refs: ["artifact://synapse/turn/test-run/1/output"],
           availability: :available
         }
       ],
       events: [
         %{
           event_ref: "event://synapse/test-run/started",
           ledger_ref: run_ref,
           event_seq: 1,
           event_kind: :run_started,
           visibility: :product,
           observed_at: @timestamp,
           summary: "Run accepted by the durable owner"
         }
       ],
       reviews: [
         %{
           review_ref: "review://synapse/test-run/effect",
           effect_ref: "effect://synapse/test-run/write",
           owner_projection_ref: "projection://mezzanine/review/test-run",
           source_contract_ref: "contract://mezzanine/review-effect/v1",
           status: :pending,
           row_version: 1,
           allowed_actions: [:approve, :reject, :amend],
           availability: :available
         }
       ],
       artifacts: [
         %{
           artifact_ref: "artifact://synapse/turn/test-run/1/output",
           owner_projection_ref: "projection://mezzanine/artifact/test-run/1/output",
           source_contract_ref: "contract://mezzanine/artifact/v1",
           kind: :turn_output,
           status: :retained,
           retained?: true,
           content_ref: "content://synapse/turn/test-run/1/output",
           content_hash: "sha256:#{String.duplicate("c", 64)}",
           retention_policy_ref: "policy://synapse/artifact/default",
           evidence_refs: ["evidence://synapse/test-run/output"],
           lineage_refs: ["turn://durable/test-run/1"],
           availability: :available
         }
       ],
       operations: [
         %{
           operation_ref: "operation://synapse/test-run/model/1",
           run_ref: run_ref,
           owner_projection_ref: "projection://mezzanine/operation/test-run/model/1",
           source_contract_ref: "contract://mezzanine/operation/v1",
           kind: :model_invocation,
           state: :completed,
           attempt_ref: "attempt://synapse/test-run/model/1",
           turn_ref: "turn://durable/test-run/1",
           receipt_ref: "receipt://synapse/test-run/model/1",
           artifact_refs: ["artifact://synapse/turn/test-run/1/output"],
           evidence_refs: ["evidence://synapse/test-run/model/1"],
           availability: :available
         }
       ],
       capabilities: capability_rows(),
       persistence_posture: PersistencePosture.durable(:runtime_projection),
       availability: :available
     }}
  end

  @impl true
  def capability_projections(_context, _request, _opts), do: {:ok, capability_rows()}

  defp cursor(run_ref) do
    %{
      cursor_ref: "cursor://synapse/test-run/1",
      ledger_ref: run_ref,
      tenant_ref: "tenant://default",
      actor_ref: "actor:synapse:operator",
      last_seq_seen: 1,
      visibility: :product
    }
  end

  defp capability_rows do
    [
      %{
        capability_ref: "capability://model/gemini-completion",
        owner_projection_ref: "projection://runtime/capability/gemini-completion",
        source_contract_ref: "contract://runtime/capability/v1",
        producer_revision_ref: "revision://jido-integration/test",
        contract_version: "1",
        kind: :model,
        configured_mode: :local_effect,
        advertised?: true,
        health_ref: "health://model/gemini-completion/ready",
        operation_refs: ["operation-class://model/completion"],
        scope_refs: ["scope://tenant/default"],
        availability: :available
      },
      %{
        capability_ref: "capability://execution/runtime-http",
        owner_projection_ref: "projection://runtime/capability/runtime-http",
        source_contract_ref: "contract://runtime/capability/v1",
        producer_revision_ref: "revision://execution-plane/test",
        contract_version: "1",
        kind: :execution_lane,
        configured_mode: :runtime_admitted,
        advertised?: false,
        operation_refs: [],
        scope_refs: [],
        availability: {:unavailable, :not_admitted}
      }
    ]
  end
end

defmodule Synapse.Test.RuntimeBackend do
  @moduledoc false
  @behaviour AppKit.Core.Backends.RuntimeBackend

  alias AppKit.Core.RuntimeSurface.RuntimeStatusSnapshot

  @impl true
  def runtime_status(context, _request, _opts) do
    RuntimeStatusSnapshot.new(%{
      tenant_ref: context.tenant_ref.id,
      program_ref: "program://test/synapse",
      health: %{
        "app_kit_surfaces" => "available",
        "durable_owner" => "available",
        "trace_export_metrics_truth" => "separate_from_ops_health"
      },
      preflight: %{"trace_export_metrics_truth" => "not_used"},
      metadata: %{"source" => "durable_test_backend"}
    })
  end

  @impl true
  def apply_runtime_profile(_context, _profile, _opts), do: {:error, :not_used}

  @impl true
  def runtime_logs(_context, _request, _opts), do: {:error, :not_used}

  @impl true
  def record_live_effect(_context, _attrs, _opts), do: {:error, :not_used}
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

  alias AppKit.Core.{
    MemoryFragmentProjection,
    MemoryFragmentProvenance,
    PersistencePosture,
    SurfaceError
  }

  @timestamp "2026-07-20T00:00:00Z"
  @proof_hash "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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

  def submit_agent_turn(context, submission, opts) do
    if pid = Keyword.get(opts, :test_pid) do
      send(pid, {:submit_agent_turn, context, submission})
    end

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

  def state_snapshot(_context, _request, opts) do
    {:ok, row} = runtime_row("run://durable/test-run")

    generic_row = %{
      row
      | subject_ref: "subject://generic/work",
        run_ref: "subject://generic/work"
    }

    rows = [row, %{generic_row | extensions: %{}}]

    rows =
      if Keyword.get(opts, :include_unavailable_run) do
        {:ok, unavailable_row} = runtime_row("run://durable/unavailable-projection")
        [unavailable_row | rows]
      else
        rows
      end

    RuntimeStateSnapshot.new(%{
      tenant_ref: "tenant://default",
      installation_ref: "installation://default",
      generated_at: @timestamp,
      rows: rows,
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

  def request_runtime_control(_context, request, _opts) do
    if map_value(request.params, :expected_control_row_version) == 2 do
      surface_error(
        "stale_control_version",
        "Run control changed; reload before retrying",
        :conflict,
        false
      )
    else
      command_result(request.action, request.idempotency_key, request.run_ref,
        workflow_effect_state: :queued_signal,
        projection_state: requested_state(request.action)
      )
    end
  end

  def list_memory_fragments(_context, request, _opts) do
    {:ok,
     [
       fragment(request.proof_token_ref, "project-fact", "fresh", "none", %{
         "title" => "Included project fact"
       }),
       fragment(request.proof_token_ref, "stale-note", "invalidation_pending", "pending", %{
         "title" => "Stale run note"
       }),
       fragment(request.proof_token_ref, "revoked-note", "fresh", "revoked", %{
         "title" => "Revoked agent note"
       }),
       fragment(request.proof_token_ref, "candidate-learning", "fresh", "none", %{
         "title" => "Candidate learning",
         "state" => "candidate"
       }),
       fragment(request.proof_token_ref, "partitioned-note", "partitioned", "unknown", %{
         "title" => "Partitioned memory"
       })
     ]}
  end

  def memory_fragment_by_proof_token(context, lookup, opts) do
    with {:ok, [fragment | _rest]} <-
           list_memory_fragments(context, %{proof_token_ref: lookup.proof_token_ref}, opts) do
      {:ok, fragment}
    end
  end

  def memory_fragment_provenance(_context, fragment_ref, _opts) do
    MemoryFragmentProvenance.new(%{
      fragment_ref: fragment_ref,
      proof_token_ref: "proof-token://synapse/test-snapshot",
      proof_hash: @proof_hash,
      source_contract_name: "OuterBrain.MemoryContextProvenance.v2",
      snapshot_epoch: 7,
      source_node_ref: "node://outer-brain/test",
      commit_lsn: "0/16B6C50",
      commit_hlc: %{"physical_ms" => 1_774_000_000_000, "logical" => 0},
      provenance_refs: ["provenance://outer-brain/#{run_token(fragment_ref)}"],
      evidence_refs: ["evidence://outer-brain/#{run_token(fragment_ref)}"],
      governance_refs: ["authority://synapse/memory-read"],
      metadata: %{"source" => "durable_test_backend"}
    })
  end

  defp runtime_row(run_ref) do
    control_state = control_state(run_ref)

    RuntimeRow.new(%{
      subject_ref: "subject://synapse/#{run_token(run_ref)}",
      run_ref: run_ref,
      workflow_ref: "workflow://durable/#{run_token(run_ref)}",
      state: :accepted,
      updated_at: @timestamp,
      persistence_posture: PersistencePosture.durable(:runtime_projection),
      extensions: %{
        agent_run_projection: %{canonical: true, owner_ref: "Test.AppKitBackend"},
        title: "Durable run #{run_token(run_ref)}",
        goal_summary: "Read from the durable AppKit projection",
        control: %{
          state: control_state,
          generation: 1,
          attempt_sequence: 1,
          sequence: 2,
          row_version: if(run_token(run_ref) == "stale-control", do: 2, else: 3),
          attempt_ref: "attempt://durable/#{run_token(run_ref)}/1",
          generation_ref: "generation://durable/#{run_token(run_ref)}/1",
          external_operation_ref: "operation://durable/#{run_token(run_ref)}",
          deadline_at: "2026-07-29T00:00:00Z",
          fence_epoch: if(control_state == "reconciling", do: 2, else: 1),
          reconciliation_attempts: if(control_state == "reconciling", do: 1, else: 0),
          terminal_receipt_ref: nil,
          last_error: control_error(control_state),
          updated_at: @timestamp
        }
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

  defp command_result(kind, idempotency_key, run_ref, opts \\ []) do
    CommandResult.new(%{
      command_ref: "command://durable/#{kind}/#{run_token(run_ref)}",
      command_kind: kind,
      accepted?: true,
      coalesced?: false,
      status: :accepted,
      authority_state: :authorized,
      authority_refs: [],
      workflow_effect_state: Keyword.get(opts, :workflow_effect_state, :applied),
      projection_state: Keyword.get(opts, :projection_state, :updated),
      correlation_id: run_ref,
      idempotency_key: idempotency_key,
      message: "Accepted by durable test backend",
      persistence_posture: PersistencePosture.durable(:runtime_projection)
    })
  end

  defp fragment(proof_token_ref, token, staleness_class, cluster_status, metadata) do
    metadata =
      metadata
      |> Map.merge(%{
        "run_ref" => "run://durable/test-run",
        "trace_id" => "trace://synapse/memory/test",
        "retrieval_snapshot_ref" => "snapshot://synapse/test-snapshot/7",
        "context_manifest_artifact_ref" => "artifact://synapse/context/test-snapshot",
        "exclusion_refs" => ["memory://durable/excluded-secret"],
        "content_artifact_ref" => "artifact://synapse/memory/#{token}",
        "content_digest" => "sha256:#{String.duplicate("b", 64)}",
        "recorded_at" => @timestamp,
        "retention_state" => "retained",
        "retention_policy_ref" => "policy://synapse/memory/default",
        "deletion_state" => "active",
        "reindex_state" => "indexed",
        "index_revision" => 12
      })
      |> Map.merge(lifecycle_metadata(token))

    {:ok, projection} =
      MemoryFragmentProjection.new(%{
        fragment_ref: "memory://durable/#{token}",
        tenant_ref: "tenant://default",
        installation_ref: "installation://default",
        tier: if(token == "candidate-learning", do: "working", else: "episodic"),
        proof_token_ref: proof_token_ref,
        proof_hash: @proof_hash,
        source_node_ref: "node://outer-brain/test",
        snapshot_epoch: 7,
        commit_lsn: "0/16B6C50",
        commit_hlc: %{"physical_ms" => 1_774_000_000_000, "logical" => 0},
        provenance_refs: ["provenance://outer-brain/#{token}"],
        evidence_refs: ["evidence://outer-brain/#{token}"],
        governance_refs: ["authority://synapse/memory-read"],
        cluster_invalidation_status: cluster_status,
        staleness_class: staleness_class,
        redaction_posture: "refs_only",
        metadata: metadata
      })

    projection
  end

  defp lifecycle_metadata("stale-note"),
    do: %{"reindex_state" => "pending", "reindex_reason" => "invalidation_pending"}

  defp lifecycle_metadata("revoked-note"),
    do: %{
      "retention_state" => "deleted",
      "deletion_state" => "tombstoned",
      "deleted_at" => @timestamp,
      "deletion_reason" => "owner_revoked"
    }

  defp lifecycle_metadata("partitioned-note"),
    do: %{"deletion_state" => "unknown", "reindex_state" => "degraded"}

  defp lifecycle_metadata(_token), do: %{}

  defp control_state(run_ref) do
    case run_token(run_ref) do
      "ambiguous" -> "outcome_unknown"
      "reconciling" -> "reconciling"
      "operator-required" -> "operator_required"
      "paused" -> "paused"
      _other -> "running"
    end
  end

  defp control_error("outcome_unknown"), do: "provider_outcome_unknown"
  defp control_error("reconciling"), do: "owner_lost_outcome_unknown"
  defp control_error("operator_required"), do: "external_operation_not_found"
  defp control_error(_state), do: nil

  defp requested_state(action) when action in [:pause, "pause"], do: :pause_requested
  defp requested_state(action) when action in [:resume, "resume"], do: :resume_requested
  defp requested_state(action) when action in [:cancel, "cancel"], do: :cancel_requested
  defp requested_state(action) when action in [:retry, "retry"], do: :retry_requested
  defp requested_state(_action), do: :supersede_requested

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

  defp map_value(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
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
