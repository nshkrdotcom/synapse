defmodule Synapse.StagedLiveBridgeIntegrationTest do
  use ExUnit.Case, async: true

  alias AppKit.Bridges.MezzanineBridge
  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias Synapse.AgentRuns

  defmodule AgentIntakeBackend do
    def start_agent_run(_context, request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:start_agent_run_request, request, opts})

      RunOutcomeFuture.new(%{
        run_ref: "run://synapse/#{request.submission_dedupe_key}",
        workflow_ref: "workflow://synapse/#{request.submission_dedupe_key}",
        accepted?: true,
        command_ref: "command://synapse/start/#{request.submission_dedupe_key}",
        correlation_id: request.correlation_id,
        governed_effect_refs: request.governed_effect_refs
      })
    end

    def submit_agent_turn(_context, _submission, _opts), do: {:error, :not_used}
    def cancel_agent_run(_context, _run_ref, _opts), do: {:error, :not_used}
    def await_agent_outcome(_context, _run_ref, _request, _opts), do: {:error, :not_used}
  end

  test "Synapse staged-live run reaches AppKit Mezzanine bridge without StackLab orchestration" do
    assert {:ok, run} =
             AgentRuns.start_run(
               %{
                 "title" => "Phase 13 bridge integration",
                 "goal_summary" => "Exercise Synapse product code against the real AppKit bridge."
               },
               backend: AgentIntakeBackend,
               effect_surface_adapter: MezzanineBridge,
               diagnostic_lane: :echo,
               run_token: "phase13-bridge",
               trace_id: "13131313131313131313131313131313",
               test_pid: self()
             )

    assert run.ref == "run://synapse/phase13-bridge"
    assert run.feature_status == :staging_live
    assert run.effect_governance_mode == :staging_live
    assert run.diagnostic_lane == :echo
    assert run.governed_effect_refs["effect_ref"] == "effect://synapse/phase13-bridge/echo"

    assert run.governed_effect_refs["command_ref"] ==
             "command://synapse/diagnostic/phase13-bridge"

    assert run.governed_effect_refs["trace_ref"] == "13131313131313131313131313131313"

    assert [%{} = effect] = run.governed_effects
    assert effect.status == "proposed"
    assert effect.metadata["diagnostic_lane"] == "echo"
    assert effect.metadata["product_slug"] == "synapse"

    assert_received {:start_agent_run_request, request, runtime_opts}
    assert request.effect_governance_mode == :staging_live
    assert request.diagnostic_lane == :echo
    assert request.governed_effect_refs == run.governed_effect_refs
    assert Keyword.fetch!(runtime_opts, :backend) == AgentIntakeBackend

    assert run.evidence_refs == ["command://synapse/start/phase13-bridge"]
  end
end
