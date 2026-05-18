defmodule Synapse.Teams do
  @moduledoc """
  Product-safe team and coordination projections.
  """

  alias AppKit.{CoordinationSurface, HiveSurface}

  @team %{
    id: "fixture-team",
    ref: "coordination-run://synapse/team/phase-7",
    title: "Fixture implementation team",
    state: :awaiting_consensus,
    feature_status: :fixture_backed,
    executable_surface: :dto_only,
    authority_ref: "authority://synapse/default",
    members: [
      %{
        id: "planner",
        agent_ref: "agent://synapse/planner",
        role_ref: "role://synapse/planner",
        state: :ready,
        current_turn_ref: "turn://synapse/team/planner/1",
        budget_ref: "budget://synapse/planner"
      },
      %{
        id: "reviewer",
        agent_ref: "agent://synapse/reviewer",
        role_ref: "role://synapse/reviewer",
        state: :waiting,
        current_turn_ref: "turn://synapse/team/reviewer/1",
        budget_ref: "budget://synapse/reviewer"
      },
      %{
        id: "verifier",
        agent_ref: "agent://synapse/verifier",
        role_ref: "role://synapse/verifier",
        state: :ready,
        current_turn_ref: "turn://synapse/team/verifier/1",
        budget_ref: "budget://synapse/verifier"
      }
    ],
    join_barrier: %{
      barrier_ref: "join-barrier://synapse/team/phase-7",
      state: :waiting_for_reviewer,
      required_count: 2,
      arrived_count: 2,
      quorum_state: :met
    },
    fanout: %{
      state: :complete,
      turn_refs: [
        "turn://synapse/team/planner/1",
        "turn://synapse/team/reviewer/1",
        "turn://synapse/team/verifier/1"
      ]
    },
    fanin: %{
      state: :awaiting_consensus,
      arbitration_ref: "arbitration://synapse/team/phase-7"
    },
    memory_grants: [
      %{
        grant_ref: "memory-grant://synapse/team/read",
        action: :read,
        status: :allowed
      },
      %{
        grant_ref: "memory-grant://synapse/team/write",
        action: :write,
        status: :denied,
        reason_codes: ["arbitration_memory_write_grant_missing"]
      }
    ]
  }

  @spec list_teams(keyword()) :: [map()]
  def list_teams(_opts \\ []), do: [team_view!(@team)]

  @spec get_team(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_team(id_or_ref, _opts \\ []) when is_binary(id_or_ref) do
    if id_or_ref in [@team.id, @team.ref] do
      {:ok, team_view!(@team)}
    else
      {:error, :team_not_found}
    end
  end

  @spec control_status() :: map()
  def control_status do
    %{
      status: :disabled,
      reason: :dto_only_coordination_surface,
      required_surface: "Executable AppKit coordination control backend"
    }
  end

  @spec request_control(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def request_control(id_or_ref, attrs, _opts \\ [])
      when is_binary(id_or_ref) and is_map(attrs) do
    with {:ok, team} <- get_team(id_or_ref),
         {:ok, request} <-
           CoordinationSurface.run_control(%{
             request_ref: "coordination-control://synapse/#{control_class(attrs)}",
             coordination_run_ref: team.ref,
             authority_ref: team.authority_ref,
             actor_ref: "actor:synapse:operator",
             control_class: control_class(attrs),
             trace_refs: ["trace://fixture/team-control"]
           }) do
      {:ok, Map.put(request, :execution_status, :disabled)}
    end
  end

  defp team_view!(attrs) do
    attrs
    |> Map.put(:coordination_projection, coordination_projection!())
    |> Map.put(:hive_projection, hive_projection!())
    |> Map.put(:control_status, control_status())
  end

  defp coordination_projection! do
    {:ok, projection} =
      CoordinationSurface.coordination_projection(%{
        coordination_run_ref: @team.ref,
        tenant_ref: "tenant://default",
        authority_ref: @team.authority_ref,
        router_decision: %{
          router_decision_ref: "router-decision://synapse/team/phase-7",
          router_artifact_ref: "router-artifact://synapse/team/default",
          selected_role_ref: "role://synapse/planner",
          confidence_band: :medium,
          trace_ref: "trace://fixture/team-router",
          replay_ref: "replay://fixture/team-router"
        },
        role_selection: %{
          role_ref: "role://synapse/planner",
          prompt_ref: "prompt://synapse/team/planner",
          capability_refs: ["capability.plan", "capability.reflect"],
          model_profile_refs: ["model-profile://synapse/planner"],
          tool_policy_ref: "tool-policy://synapse/team/default",
          memory_profile_ref: "memory-profile://synapse/default",
          guardrail_profile_ref: "guardrail://synapse/default",
          verifier_profile_ref: "verifier://synapse/default",
          budget_ref: "budget://synapse/planner",
          context_budget_ref: "context-budget://synapse/default",
          handoff_policy_ref: "handoff://synapse/default",
          gepa_target_refs: ["optimization-target://synapse/planner"]
        },
        provider_pool: %{
          provider_pool_ref: "provider-pool://synapse/catalog/default",
          slot_refs: ["slot://synapse/planner"],
          model_profile_refs: ["model-profile://synapse/planner"],
          endpoint_profile_refs: ["endpoint-profile://synapse/default"],
          operation_policy_refs: ["operation-policy://synapse/planner"],
          readiness_refs: ["readiness://catalog/ready"]
        },
        verifier_state: %{
          verifier_policy_ref: "verifier-policy://synapse/default",
          verifier_result_ref: "verifier-result://synapse/team/phase-7",
          score_schema_ref: "score-schema://synapse/default",
          termination_policy_ref: "termination-policy://synapse/default",
          replay_ref: "replay://fixture/team-verifier",
          trace_ref: "trace://fixture/team-verifier"
        },
        turn_timeline: %{
          turn_refs: @team.fanout.turn_refs,
          agent_refs: Enum.map(@team.members, & &1.agent_ref),
          inference_call_refs: ["inference-call://fixture/team/planner"],
          verifier_refs: ["verifier-result://synapse/team/phase-7"],
          handoff_refs: ["handoff://synapse/team/planner-to-reviewer"],
          trace_refs: ["trace://fixture/team-turns"]
        },
        memory_refs: ["memory://fixture/included-project-fact"],
        context_budget_refs: ["context-budget://synapse/default"],
        replay_bundle: %{
          replay_bundle_ref: "replay-bundle://synapse/team/phase-7",
          coordination_run_ref: @team.ref,
          trace_refs: ["trace://fixture/team-replay"],
          replay_refs: ["replay://fixture/team-replay"],
          redaction_posture: :refs_only
        },
        trace_refs: ["trace://fixture/team"]
      })

    projection
  end

  defp hive_projection! do
    {:ok, projection} =
      HiveSurface.projection(%{
        projection_ref: "hive-projection://synapse/team/phase-7",
        tenant_ref: "tenant://default",
        installation_ref: "installation://default",
        agent_refs: Enum.map(@team.members, & &1.agent_ref),
        message_refs: ["message://synapse/team/planner-summary"],
        memory_scope_refs: ["memory-scope://synapse/team"],
        pattern_refs: ["coordination-pattern://synapse/fanout-fanin"],
        budget_refs: Enum.map(@team.members, & &1.budget_ref),
        trace_refs: ["trace://fixture/team"],
        redaction_posture: "refs_only"
      })

    projection
  end

  defp control_class(%{"control_class" => "pause"}), do: :pause
  defp control_class(%{"control_class" => "resume"}), do: :resume
  defp control_class(%{"control_class" => "cancel"}), do: :cancel
  defp control_class(%{control_class: :pause}), do: :pause
  defp control_class(%{control_class: :resume}), do: :resume
  defp control_class(%{control_class: :cancel}), do: :cancel
  defp control_class(_attrs), do: :pause
end
