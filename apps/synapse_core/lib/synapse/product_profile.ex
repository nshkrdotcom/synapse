defmodule Synapse.ProductProfile do
  @moduledoc """
  Product-owned role, team, feature, and install profile data.
  """

  alias Synapse.{Config, ProductPack}

  @feature_status %{
    installation: :fixture_backed,
    runs: :fixture_backed,
    turns: :fixture_backed,
    cancel_refresh: :fixture_backed,
    reviews: :fixture_backed,
    memory: :disabled,
    memory_feedback: :disabled,
    context_pack: :disabled,
    tools: :roadmap,
    models: :roadmap,
    catalog: :roadmap,
    teams: :roadmap,
    arbitration: :roadmap,
    evidence: :fixture_backed,
    operations: :fixture_backed,
    live_run_slice: :live_stack_deterministic,
    stack_lab: :live_stack_deterministic
  }

  @roles [
    %{
      ref: :coordinator,
      display_name: "Coordinator",
      prompt_ref: :coordinator_prompt_v1,
      model_profile_ref: :balanced_reasoning,
      context_policy_ref: :task_scope_context,
      budget_class: :standard_agent_run,
      tool_capability_refs: [:task_planning, :context_pack_read],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:final_effect_review],
      evidence_requirements: [:run_receipt, :decision_record],
      allowed_input_classes: [:operator_request, :source_item],
      allowed_output_classes: [:execution_plan, :delegation_plan],
      failure_posture: :fail_closed
    },
    %{
      ref: :research_specialist,
      display_name: "Research Specialist",
      prompt_ref: :research_prompt_v1,
      model_profile_ref: :deep_research,
      context_policy_ref: :research_context,
      budget_class: :research_agent_run,
      tool_capability_refs: [:context_pack_read, :catalog_read],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [:research_note_candidate],
      review_gate_refs: [:memory_promotion_review],
      evidence_requirements: [:source_summary, :run_receipt],
      allowed_input_classes: [:research_question],
      allowed_output_classes: [:research_brief, :evidence_summary],
      failure_posture: :degrade
    },
    %{
      ref: :implementation_specialist,
      display_name: "Implementation Specialist",
      prompt_ref: :implementation_prompt_v1,
      model_profile_ref: :code_execution,
      context_policy_ref: :implementation_context,
      budget_class: :implementation_agent_run,
      tool_capability_refs: [:workspace_edit, :test_execution],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:external_effect_review],
      evidence_requirements: [:change_summary, :test_receipt],
      allowed_input_classes: [:implementation_task],
      allowed_output_classes: [:patch_summary, :verification_receipt],
      failure_posture: :retry
    },
    %{
      ref: :security_specialist,
      display_name: "Security Specialist",
      prompt_ref: :security_review_prompt_v1,
      model_profile_ref: :security_review,
      context_policy_ref: :security_context,
      budget_class: :review_agent_run,
      tool_capability_refs: [:static_review, :policy_read],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:security_escalation_review],
      evidence_requirements: [:security_findings],
      allowed_input_classes: [:patch_summary, :risk_profile],
      allowed_output_classes: [:risk_finding, :approval_posture],
      failure_posture: :fail_closed
    },
    %{
      ref: :performance_specialist,
      display_name: "Performance Specialist",
      prompt_ref: :performance_review_prompt_v1,
      model_profile_ref: :performance_review,
      context_policy_ref: :performance_context,
      budget_class: :review_agent_run,
      tool_capability_refs: [:metric_read, :test_execution],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:performance_escalation_review],
      evidence_requirements: [:performance_findings],
      allowed_input_classes: [:patch_summary, :metric_snapshot],
      allowed_output_classes: [:performance_finding, :approval_posture],
      failure_posture: :degrade
    },
    %{
      ref: :documentation_specialist,
      display_name: "Documentation Specialist",
      prompt_ref: :documentation_prompt_v1,
      model_profile_ref: :documentation_generation,
      context_policy_ref: :documentation_context,
      budget_class: :standard_agent_run,
      tool_capability_refs: [:doc_read, :doc_write_candidate],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [:documentation_note_candidate],
      review_gate_refs: [:final_effect_review],
      evidence_requirements: [:documentation_delta],
      allowed_input_classes: [:documentation_task],
      allowed_output_classes: [:guide_patch, :summary],
      failure_posture: :degrade
    },
    %{
      ref: :review_synthesizer,
      display_name: "Review Synthesizer",
      prompt_ref: :review_synthesis_prompt_v1,
      model_profile_ref: :review_synthesis,
      context_policy_ref: :review_context,
      budget_class: :review_agent_run,
      tool_capability_refs: [:evidence_read, :decision_prepare],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:operator_final_review],
      evidence_requirements: [:review_record],
      allowed_input_classes: [:agent_output_set],
      allowed_output_classes: [:decision_recommendation],
      failure_posture: :fail_closed
    },
    %{
      ref: :arbitration_chair,
      display_name: "Arbitration Chair",
      prompt_ref: :arbitration_prompt_v1,
      model_profile_ref: :arbitration_reasoning,
      context_policy_ref: :arbitration_context,
      budget_class: :high_risk_agent_run,
      tool_capability_refs: [:evidence_read, :policy_read],
      memory_read_grant_refs: [:project_memory_read],
      memory_write_grant_refs: [],
      review_gate_refs: [:arbitration_final_review],
      evidence_requirements: [:arbitration_record, :decision_record],
      allowed_input_classes: [:conflicting_findings],
      allowed_output_classes: [:arbitration_position, :final_recommendation],
      failure_posture: :fail_closed
    }
  ]

  @team_templates [
    %{
      ref: :fast_review,
      display_name: "Fast Review",
      role_refs: [:coordinator, :review_synthesizer],
      execution_posture: :fixture_until_team_surface_live
    },
    %{
      ref: :standard_implementation,
      display_name: "Standard Implementation",
      role_refs: [:coordinator, :implementation_specialist, :review_synthesizer],
      execution_posture: :fixture_until_team_surface_live
    },
    %{
      ref: :high_risk_change,
      display_name: "High-Risk Change",
      role_refs: [
        :coordinator,
        :implementation_specialist,
        :security_specialist,
        :performance_specialist,
        :review_synthesizer
      ],
      execution_posture: :fixture_until_team_surface_live
    },
    %{
      ref: :documentation_research,
      display_name: "Documentation/Research",
      role_refs: [
        :coordinator,
        :research_specialist,
        :documentation_specialist,
        :review_synthesizer
      ],
      execution_posture: :fixture_until_team_surface_live
    }
  ]

  @spec feature_status() :: map()
  def feature_status, do: @feature_status

  @spec roles() :: [map()]
  def roles, do: @roles

  @spec team_templates() :: [map()]
  def team_templates, do: @team_templates

  @spec profile(Config.t() | keyword() | map()) :: map()
  def profile(%Config{} = config) do
    %{
      program: %{
        slug: config.product_slug,
        name: config.product_name,
        product_family: config.product_family,
        configuration: %{
          "pack_slug" => ProductPack.pack_slug(config),
          "pack_version" => ProductPack.pack_version(config),
          "bootstrap_mode" => Atom.to_string(config.bootstrap_mode),
          "default_installation_id" => config.default_installation_id,
          "operator_surface_enabled" => config.operator_surface_enabled?
        },
        metadata: %{
          "product" => "synapse",
          "profile" => "default",
          "pack_slug" => ProductPack.pack_slug(config),
          "pack_version" => ProductPack.pack_version(config)
        }
      },
      roles: @roles,
      team_templates: @team_templates,
      feature_status: @feature_status
    }
  end

  def profile(overrides), do: overrides |> Config.load() |> profile()
end
