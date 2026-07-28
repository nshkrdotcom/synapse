defmodule Synapse.GovernedEffectsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.{
    EffectAcceptanceDTO,
    EffectDispatchCommandDTO,
    EffectReceiptCommandDTO,
    GovernedEffectDTO,
    GovernedEffectProposalDTO,
    RequestContext
  }

  alias Synapse.GovernedEffects

  @manifest_hash "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @content_digest "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @owner_ref "effect-execution://00000000-0000-0000-0000-000000000004"

  defmodule RecordingEffectBackend do
    @behaviour AppKit.EffectSurface

    @impl true
    def propose_effect(_context, %GovernedEffectProposalDTO{} = proposal, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:propose_effect, proposal})
      projection(:authorized, 1, :pending)
    end

    @impl true
    def begin_dispatch(
          _context,
          owner_ref,
          %EffectDispatchCommandDTO{} = command,
          opts
        ) do
      send(Keyword.fetch!(opts, :test_pid), {:begin_dispatch, owner_ref, command})
      projection(:dispatching, command.expected_row_version + 1, :accepted)
    end

    @impl true
    def record_accepted(
          _context,
          owner_ref,
          %EffectAcceptanceDTO{} = acceptance,
          opts
        ) do
      send(Keyword.fetch!(opts, :test_pid), {:record_accepted, owner_ref, acceptance})
      projection(:running, acceptance.expected_row_version + 1, :accepted)
    end

    @impl true
    def record_receipt(
          _context,
          owner_ref,
          %EffectReceiptCommandDTO{} = receipt,
          opts
        ) do
      send(Keyword.fetch!(opts, :test_pid), {:record_receipt, owner_ref, receipt})
      projection(:ambiguous, receipt.expected_row_version + 1, :accepted, ambiguous_attrs())
    end

    @impl true
    def get_effect(_context, owner_ref, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:get_effect, owner_ref})

      case Keyword.get(opts, :readback_state, :ambiguous) do
        :authorized -> projection(:authorized, 1, :pending)
        :dispatching -> projection(:dispatching, 2, :accepted)
        :running -> projection(:running, 3, :accepted)
        :ambiguous -> projection(:ambiguous, 4, :accepted, ambiguous_attrs())
      end
    end

    @impl true
    def get_effect_by_idempotency(_context, key, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:get_effect_by_idempotency, key})
      projection(:ambiguous, 4, :accepted, ambiguous_attrs())
    end

    def projection(status, row_version, review_status, extra \\ %{}) do
      GovernedEffectDTO.new(
        Map.merge(
          %{
            contract_version: 1,
            effect_ref: "effect://synapse/reviewed-file",
            run_ref: "run://synapse/reviewed-file",
            turn_ref: "turn://synapse/reviewed-file/1",
            command_ref: "command://synapse/reviewed-file",
            decision_ref: "decision://synapse/reviewed-file",
            grant_ref: "grant://synapse/reviewed-file",
            target_ref: "target://codex/local/reviewed-file",
            owner_execution_ref: "effect-execution://00000000-0000-0000-0000-000000000004",
            status: Atom.to_string(status),
            row_version: row_version,
            attempt_ref: "attempt://synapse/reviewed-file/1",
            pinned_tool_manifest: %{
              manifest_ref: "manifest://synapse/codex/reviewed-file",
              manifest_hash:
                "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              action_ids: ["create_or_replace_one_named_text_file"]
            },
            reviewed_operation: %{
              operation: "create_or_replace",
              workspace_ref: "workspace://synapse/reviewed-file",
              file_ref: "file://synapse/RESULT.txt",
              relative_path: "RESULT.txt",
              content_digest:
                "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            },
            review: %{
              review_ref: "review://synapse/reviewed-file",
              review_unit_id: "review-unit-synapse-reviewed-file",
              status: Atom.to_string(review_status),
              row_version: if(review_status == :pending, do: 1, else: 2),
              accepted_actor_ref:
                if(review_status == :accepted, do: "actor:synapse:operator", else: nil)
            }
          },
          extra
        )
      )
    end

    defp ambiguous_attrs do
      %{
        receipt: %{
          receipt_ref: "receipt://synapse/reviewed-file/ambiguous",
          effect_ref: "effect://synapse/reviewed-file",
          status: "ambiguous",
          attempt_ref: "attempt://synapse/reviewed-file/1",
          cleanup: %{
            status: "completed",
            cleanup_ref: "cleanup://synapse/reviewed-file",
            session_terminated: true,
            materialization_removed: true,
            credential_lease_released: true
          }
        },
        ambiguity: %{
          effect_ref: "effect://synapse/reviewed-file",
          state: "outcome_unknown",
          continuation_ref: "continuation://synapse/reviewed-file",
          reconciliation_required: true,
          effect_retry_allowed: false
        },
        continuation: %{
          continuation_ref: "continuation://synapse/reviewed-file",
          status: "pending",
          target_kind: "owner_command",
          target_owner: "jido_integration",
          target_operation: "reconcile_effect_outcome",
          idempotency_key: "synapse-reconcile-reviewed-file",
          attempt_count: 0
        }
      }
    end
  end

  test "drives reviewed effect proposal and every durable transition through AppKit" do
    opts = surface_opts(self())

    assert {:ok, opened} =
             GovernedEffects.propose_reviewed_file_effect(context!(), proposal(), opts)

    assert opened.status == "authorized"
    assert opened.review.status == "pending"
    assert opened.reviewed_operation["content_digest"] == @content_digest
    refute Map.has_key?(opened.reviewed_operation, "content")

    assert_receive {:propose_effect, %GovernedEffectProposalDTO{}}

    assert {:ok, dispatching} =
             GovernedEffects.begin_dispatch(
               @owner_ref,
               Keyword.put(opts, :readback_state, :authorized)
             )

    assert dispatching.status == "dispatching"

    assert_receive {:get_effect, @owner_ref}

    assert_receive {:begin_dispatch, @owner_ref,
                    %EffectDispatchCommandDTO{expected_row_version: 1}}

    assert {:ok, running} =
             GovernedEffects.record_accepted(
               @owner_ref,
               %{
                 attempt_ref: "attempt://synapse/reviewed-file/1",
                 external_ref: "codex-thread://synapse/reviewed-file",
                 accepted_receipt_ref: "receipt://synapse/reviewed-file/accepted"
               },
               Keyword.put(opts, :readback_state, :dispatching)
             )

    assert running.status == "running"
    assert_receive {:get_effect, @owner_ref}
    assert_receive {:record_accepted, @owner_ref, %EffectAcceptanceDTO{expected_row_version: 2}}

    assert {:ok, ambiguous} =
             GovernedEffects.record_receipt(
               @owner_ref,
               %{
                 receipt_ref: "receipt://synapse/reviewed-file/ambiguous",
                 receipt_state: "ambiguous",
                 ambiguity_state: "outcome_unknown",
                 continuation_target: %{
                   kind: "owner_command",
                   owner: "jido_integration",
                   command: "reconcile_effect_outcome",
                   idempotency_key: "synapse-reconcile-reviewed-file"
                 },
                 cleanup: %{
                   status: "completed",
                   cleanup_ref: "cleanup://synapse/reviewed-file",
                   session_terminated: true,
                   materialization_removed: true,
                   credential_lease_released: true
                 }
               },
               Keyword.put(opts, :readback_state, :running)
             )

    assert ambiguous.status == "ambiguous"
    assert ambiguous.receipt.cleanup.materialization_removed
    assert ambiguous.ambiguity.reconciliation_required
    refute ambiguous.ambiguity.effect_retry_allowed
    assert ambiguous.continuation.target_operation == "reconcile_effect_outcome"

    assert_receive {:get_effect, @owner_ref}

    assert_receive {:record_receipt, @owner_ref,
                    %EffectReceiptCommandDTO{expected_row_version: 3}}
  end

  test "approves only the exact immutable manifest and reviewed operation" do
    {:ok, effect} = RecordingEffectBackend.projection(:authorized, 1, :pending)

    assert {:ok, result} =
             GovernedEffects.approve_reviewed_operation(
               @owner_ref,
               %{reason: "Exact digest reviewed", actor_ref: "operator://synapse/reviewer"},
               effect_surface_adapter: RecordingEffectBackend,
               review_backend: Synapse.Test.ReviewBackend,
               test_pid: self(),
               readback_state: :authorized,
               program_id: "program://test/synapse"
             )

    assert result.status == :completed

    assert_receive {:get_effect, @owner_ref}
    assert_receive {:review_decision, "review-unit-synapse-reviewed-file", attrs}
    assert attrs.decision == :accept
    assert attrs.payload["effect_ref"] == effect.effect_ref
    assert attrs.payload["pinned_tool_manifest"] == effect.pinned_tool_manifest
    assert attrs.payload["reviewed_operation"] == effect.reviewed_operation
    refute Map.has_key?(attrs.payload["reviewed_operation"], "content")
  end

  test "reads receipt, ambiguity, and continuation by owner and idempotency identity" do
    opts = surface_opts(self())

    assert {:ok, by_owner} = GovernedEffects.get_effect(@owner_ref, opts)

    assert {:ok, by_idempotency} =
             GovernedEffects.get_effect_by_idempotency(
               "synapse-reviewed-file-effect",
               opts
             )

    assert by_owner == by_idempotency
    assert by_owner.receipt.receipt_ref == "receipt://synapse/reviewed-file/ambiguous"
    assert by_owner.ambiguity.state == "outcome_unknown"
    assert by_owner.continuation.status == "pending"
    assert_receive {:get_effect, @owner_ref}
    assert_receive {:get_effect_by_idempotency, "synapse-reviewed-file-effect"}
  end

  test "rejects raw effect material before dispatch" do
    unsafe = Map.put(proposal(), :content, "must not cross AppKit")

    assert {:error, :invalid_governed_effect_proposal} =
             GovernedEffects.propose_reviewed_file_effect(
               context!(),
               unsafe,
               surface_opts(self())
             )

    refute_received {:propose_effect, _proposal}
  end

  defp surface_opts(pid) do
    [
      effect_surface_adapter: RecordingEffectBackend,
      test_pid: pid,
      program_id: "program://test/synapse",
      work_class_id: "work-class://test/reviewed-effect",
      trace_id: "0123456789abcdef0123456789abcdef",
      idempotency_key: "synapse-reviewed-file-effect"
    ]
  end

  defp context! do
    {:ok, context} =
      RequestContext.new(%{
        trace_id: "0123456789abcdef0123456789abcdef",
        actor_ref: %{id: "actor:synapse:operator", kind: :human},
        tenant_ref: %{id: "default"},
        installation_ref: %{id: "default", pack_slug: "nshkr-agent"},
        idempotency_key: "synapse-reviewed-file-effect"
      })

    context
  end

  defp proposal do
    %{
      effect_ref: "effect://synapse/reviewed-file",
      run_ref: "run://synapse/reviewed-file",
      turn_ref: "turn://synapse/reviewed-file/1",
      command_ref: "command://synapse/reviewed-file",
      decision_ref: "decision://synapse/reviewed-file",
      grant_ref: "grant://synapse/reviewed-file",
      review_ref: "review://synapse/reviewed-file",
      subject_id: "subject-synapse-reviewed-file",
      run_id: "run-synapse-reviewed-file",
      review_unit_id: "review-unit-synapse-reviewed-file",
      target_ref: "target://codex/local/reviewed-file",
      attempt_ref: "attempt://synapse/reviewed-file/1",
      capability_id: "codex.session.turn",
      effect_mode: "managed_account_local_effect",
      pinned_tool_manifest: %{
        manifest_ref: "manifest://synapse/codex/reviewed-file",
        manifest_hash: @manifest_hash,
        action_ids: ["create_or_replace_one_named_text_file"]
      },
      reviewed_operation: %{
        operation: "create_or_replace",
        workspace_ref: "workspace://synapse/reviewed-file",
        file_ref: "file://synapse/RESULT.txt",
        relative_path: "RESULT.txt",
        content_digest: @content_digest
      }
    }
  end
end
