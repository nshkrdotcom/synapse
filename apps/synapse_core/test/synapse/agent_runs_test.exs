defmodule Synapse.AgentRunsTest do
  use ExUnit.Case, async: true

  alias AppKit.BackendStack
  alias AppKit.Core.{EffectTimelineDTO, GovernedEffectDTO}
  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.AgentRuns

  defmodule ExplicitRuntimeBackend do
    def start_agent_run(_context, request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:start_agent_run_request, request, opts})
      send(Keyword.fetch!(opts, :test_pid), {:start_agent_run, request.params, opts})

      RunOutcomeFuture.new(%{
        run_ref: "run://live-stack/#{request.submission_dedupe_key}",
        workflow_ref: "workflow://live-stack/#{request.submission_dedupe_key}",
        accepted?: true,
        command_ref: "command://live-stack/start/#{request.submission_dedupe_key}",
        correlation_id: request.correlation_id,
        governed_effect_refs: request.governed_effect_refs
      })
    end

    def submit_agent_turn(_context, _submission, _opts), do: {:error, :not_used}

    def cancel_agent_run(_context, run_ref, _opts) do
      CommandResult.new(%{
        command_ref: "command://live-stack/cancel",
        command_kind: :cancel,
        accepted?: true,
        coalesced?: false,
        status: :accepted,
        authority_state: :local_policy,
        authority_refs: [],
        workflow_effect_state: "pending_signal",
        projection_state: :pending,
        correlation_id: run_ref,
        idempotency_key: "cancel:#{run_ref}",
        message: "cancel accepted"
      })
    end

    def await_agent_outcome(_context, run_ref, request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:await_agent_outcome, run_ref, request})

      {:ok,
       %{
         run_ref: run_ref,
         workflow_ref: Map.get(request, :workflow_ref),
         status: :accepted
       }}
    end
  end

  defmodule EffectSurfaceBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, attrs, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:propose_effect, attrs, opts})

      attrs
      |> Map.merge(%{
        status: "authorized",
        receipt_ref: "receipt://synapse/effects/diagnostic",
        authority_ref: "authority://synapse/effects/diagnostic",
        dispatch_ref: "dispatch://synapse/effects/diagnostic"
      })
      |> GovernedEffectDTO.new()
    end

    def get_effect(_context, effect_ref, _opts) do
      GovernedEffectDTO.new(%{
        effect_ref: effect_ref,
        effect_type: "diagnostic.echo",
        command_ref: "command://synapse/diagnostic",
        tenant_ref: "tenant://default",
        status: "completed",
        trace_ref: "trace://synapse/diagnostic",
        receipt_ref: "receipt://synapse/effects/diagnostic"
      })
    end

    def list_effects(_context, _run_ref, _opts), do: {:ok, []}

    def get_effect_timeline(_context, effect_ref, _opts) do
      EffectTimelineDTO.new(%{
        effect_ref: effect_ref,
        trace_summary_hash: "sha256:synapse-diagnostic",
        entries:
          Enum.with_index(
            [
              "proposed",
              "authorized",
              "dispatched",
              "receipt_received",
              "reduced",
              "projected",
              "completed"
            ],
            1
          )
          |> Enum.map(fn {status, sequence} ->
            %{
              "sequence" => sequence,
              "event_kind" => "effect_transition",
              "status" => status,
              "entry_hash" => "sha256:synapse-diagnostic-#{sequence}"
            }
          end),
        metadata: %{"source" => "test"}
      })
    end
  end

  defmodule FailingEffectSurfaceBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, _attrs, _opts), do: {:error, :authority_denied}
    def get_effect(_context, _effect_ref, _opts), do: {:error, :not_used}
    def list_effects(_context, _run_ref, _opts), do: {:error, :not_used}
    def get_effect_timeline(_context, _effect_ref, _opts), do: {:error, :not_used}
  end

  test "lists fixture-backed product-safe runs" do
    [run] = AgentRuns.list_runs()

    assert run.ref == "run://fixture/phase-3"
    assert run.surface == "AppKit.AgentIntake"
    assert run.authority_state == :authorized
  end

  test "starts a fixture-backed run through AgentIntake DTOs" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Check the product boundary", "goal_summary" => "Use AppKit only"},
               run_token: "phase-3-test"
             )

    assert run.ref == "run://fixture/phase-3-test"
    assert run.state == :accepted
    assert run.surface == "AppKit.AgentIntake"
  end

  test "passes explicit live-stack runtime material without defaulting to fixtures" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Live stack path", "goal_summary" => "Use explicit runtime opts"},
               backend: ExplicitRuntimeBackend,
               runtime_adapter: ExplicitRuntimeBackend,
               runtime_binding: %{runtime_binding_ref: "runtime-binding://test/agent-loop"},
               runtime_params: %{fixture_script: "success_first_try", max_turns: 2},
               live_stack?: true,
               run_token: "explicit-live-stack",
               test_pid: self()
             )

    assert run.ref == "run://live-stack/explicit-live-stack"
    assert run.feature_status == :live_stack_deterministic
    assert_received {:start_agent_run, params, opts}
    assert params.fixture_script == "success_first_try"
    assert params.max_turns == 2
    assert Keyword.fetch!(opts, :runtime_adapter) == ExplicitRuntimeBackend
    assert Keyword.fetch!(opts, :runtime_binding).runtime_binding_ref =~ "runtime-binding://test"
  end

  test "starts a staged-live diagnostic run through EffectSurface before AgentIntake" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Diagnostic run", "goal_summary" => "Use governed effect path"},
               backend: ExplicitRuntimeBackend,
               effect_surface_adapter: EffectSurfaceBackend,
               diagnostic_lane: :echo,
               run_token: "diagnostic-live",
               test_pid: self()
             )

    assert run.ref == "run://live-stack/diagnostic-live"
    assert run.feature_status == :staging_live
    assert run.diagnostic_lane == :echo
    assert run.effect_governance_mode == :staging_live
    assert run.governed_effect_refs["effect_ref"] == "effect://synapse/diagnostic-live/echo"
    assert "receipt://synapse/effects/diagnostic" in run.evidence_refs

    assert_received {:propose_effect, effect_attrs, effect_opts}
    assert effect_attrs.effect_type == "diagnostic.echo"
    assert effect_attrs.metadata["diagnostic_lane"] == "echo"
    assert Keyword.fetch!(effect_opts, :effect_surface_adapter) == EffectSurfaceBackend

    assert_received {:start_agent_run_request, request, runtime_opts}
    assert request.effect_governance_mode == :staging_live
    assert request.diagnostic_lane == :echo
    assert request.governed_effect_refs["effect_ref"] == run.governed_effect_refs["effect_ref"]
    assert Keyword.fetch!(runtime_opts, :backend) == ExplicitRuntimeBackend
  end

  test "staged-live diagnostic run can select backends through BackendStack" do
    stack =
      BackendStack.new!(
        agent_intake_backend: ExplicitRuntimeBackend,
        effect_surface_backend: EffectSurfaceBackend
      )

    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Diagnostic stack run", "goal_summary" => "Use backend stack"},
               backend_stack: stack,
               diagnostic_lane: "probe",
               run_token: "diagnostic-stack",
               test_pid: self()
             )

    assert run.ref == "run://live-stack/diagnostic-stack"
    assert run.feature_status == :staging_live
    assert run.diagnostic_lane == :probe

    assert_received {:propose_effect, effect_attrs, _effect_opts}
    assert effect_attrs.effect_type == "diagnostic.probe"

    assert_received {:start_agent_run_request, request, runtime_opts}
    assert request.diagnostic_lane == :probe
    assert Keyword.fetch!(runtime_opts, :backend_stack) == stack
  end

  test "diagnostic run falls back to fixture path when live backends are unavailable" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Fixture fallback", "goal_summary" => "No live effect backend"},
               diagnostic_lane: :echo,
               run_token: "diagnostic-fixture"
             )

    assert run.ref == "run://fixture/diagnostic-fixture"
    assert run.feature_status == :fixture_backed
    refute Map.has_key?(run, :governed_effect_refs)
  end

  test "effect proposal failure returns an explicit product error state" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{"title" => "Denied diagnostic", "goal_summary" => "Authority denial"},
               backend: ExplicitRuntimeBackend,
               effect_surface_adapter: FailingEffectSurfaceBackend,
               diagnostic_lane: :echo,
               run_token: "diagnostic-denied",
               test_pid: self()
             )

    assert run.state == :effect_proposal_failed
    assert run.feature_status == :staging_live_error
    assert run.error.reason == :authority_denied
    assert run.diagnostic_lane == :echo
    refute_received {:start_agent_run_request, _request, _opts}
  end

  test "refresh and cancel return AppKit command results" do
    assert {:ok, refresh} = AgentRuns.refresh_run("phase-3")
    assert %CommandResult{} = refresh
    assert refresh.command_kind == :refresh
    assert refresh.accepted? == true

    assert {:ok, cancel} = AgentRuns.cancel_run("phase-3")
    assert %CommandResult{} = cancel
    assert cancel.command_kind == :cancel
    assert cancel.accepted? == true
  end

  test "awaits a run through the explicitly supplied AgentIntake backend" do
    assert {:ok, result} =
             AgentRuns.await_run(
               "run://live-stack/explicit-live-stack",
               %{workflow_ref: "workflow://live-stack/explicit-live-stack"},
               backend: ExplicitRuntimeBackend,
               runtime_adapter: ExplicitRuntimeBackend,
               test_pid: self()
             )

    assert result.status == :accepted
    assert result.workflow_ref == "workflow://live-stack/explicit-live-stack"

    assert_received {:await_agent_outcome, "run://live-stack/explicit-live-stack",
                     %{workflow_ref: "workflow://live-stack/explicit-live-stack"}}
  end
end
