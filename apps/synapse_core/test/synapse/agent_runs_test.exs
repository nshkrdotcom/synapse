defmodule Synapse.AgentRunsTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.CommandResult
  alias Synapse.AgentRuns

  defmodule ExplicitRuntimeBackend do
    def start_agent_run(_context, request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:start_agent_run, request.params, opts})

      RunOutcomeFuture.new(%{
        run_ref: "run://live-stack/#{request.submission_dedupe_key}",
        workflow_ref: "workflow://live-stack/#{request.submission_dedupe_key}",
        accepted?: true,
        command_ref: "command://live-stack/start/#{request.submission_dedupe_key}",
        correlation_id: request.correlation_id
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
