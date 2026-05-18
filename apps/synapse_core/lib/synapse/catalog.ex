defmodule Synapse.Catalog do
  @moduledoc """
  Product-safe tool, model, budget, and eligibility catalog projections.
  """

  alias AppKit.{BudgetSurface, ContextBudgetSurface, CostSurface, ModelSurface, SkillSurface}

  @tenant_ref "tenant://default"
  @authority_ref "authority://synapse/default"
  @installation_ref "installation://default"
  @trace_ref "trace://fixture/catalog"

  @raw_keys [
    :api_key,
    :auth_header,
    :body,
    :credential,
    :credentials,
    :payload,
    :provider_payload,
    :raw_body,
    :raw_payload,
    :secret,
    :token,
    "api_key",
    "auth_header",
    "body",
    "credential",
    "credentials",
    "payload",
    "provider_payload",
    "raw_body",
    "raw_payload",
    "secret",
    "token"
  ]

  @catalog_items [
    %{
      id: "planner-model",
      kind: :model,
      ref: "model-profile://synapse/planner",
      title: "Planner model profile",
      status: :allowed,
      eligibility_ref: "eligibility://synapse/planner-model",
      reason_codes: [],
      posture: %{budget: :allow, quota: :within_limit, residency: :approved}
    },
    %{
      id: "summarizer-model",
      kind: :model,
      ref: "model-profile://synapse/summarizer",
      title: "Summarizer model profile",
      status: :allowed,
      eligibility_ref: "eligibility://synapse/summarizer-model",
      reason_codes: [],
      posture: %{budget: :allow_warn_soft, quota: :within_limit, residency: :approved}
    },
    %{
      id: "document-summary-tool",
      kind: :tool,
      ref: "skill://synapse/document-summary",
      title: "Document summary skill",
      status: :allowed,
      eligibility_ref: "eligibility://synapse/document-summary-tool",
      reason_codes: [],
      posture: %{budget: :allow, quota: :within_limit, residency: :approved}
    },
    %{
      id: "external-write-tool",
      kind: :tool,
      ref: "skill://synapse/external-write",
      title: "External write skill",
      status: :denied,
      eligibility_ref: "eligibility://synapse/external-write-tool",
      reason_codes: ["effect_write_grant_missing", "operator_review_required"],
      posture: %{budget: :deny_policy, quota: :not_applicable, residency: :review_required}
    }
  ]

  @spec catalog(keyword()) :: map()
  def catalog(_opts \\ []) do
    %{
      status: :fixture_backed,
      model_catalog: model_catalog!(),
      skills: skill_projections!(),
      tool_grants: tool_grants!(),
      eligibility: @catalog_items,
      budgets: budgets!(),
      costs: costs!(),
      assignment_status: assignment_status()
    }
  end

  @spec list_entries(keyword()) :: [map()]
  def list_entries(_opts \\ []), do: @catalog_items

  @spec get_eligibility(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_eligibility(id_or_ref, _opts \\ []) when is_binary(id_or_ref) do
    case Enum.find(@catalog_items, &(&1.id == id_or_ref or &1.ref == id_or_ref)) do
      nil -> {:error, :catalog_eligibility_not_found}
      item -> {:ok, eligibility_detail!(item)}
    end
  end

  @spec assignment_status() :: map()
  def assignment_status do
    %{
      status: :disabled,
      reason: :governed_assignment_surface_not_proven,
      required_surface: "AppKit governed catalog assignment backend"
    }
  end

  @spec reject_raw_payload(map()) :: :ok | {:error, term()}
  def reject_raw_payload(attrs) when is_map(attrs) do
    case Enum.find(@raw_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_catalog_payload_forbidden, key}}
    end
  end

  defp model_catalog! do
    {:ok, catalog} =
      ModelSurface.catalog_projection(%{
        tenant_ref: @tenant_ref,
        authority_ref: @authority_ref,
        model_profiles: model_profile_attrs(),
        endpoint_profiles: endpoint_profile_attrs(),
        trace_refs: [@trace_ref]
      })

    catalog
  end

  defp skill_projections! do
    Enum.map(skill_manifest_attrs(), fn attrs ->
      {:ok, projection} = SkillSurface.projection(attrs)
      projection
    end)
  end

  defp tool_grants! do
    Enum.map(skill_projections!(), fn skill ->
      %{
        id: skill.skill_ref |> String.split("/", trim: true) |> List.last(),
        skill_ref: skill.skill_ref,
        status: grant_status(skill.skill_ref),
        tool_refs: skill.tool_refs,
        capability_refs: skill.capability_refs,
        budget_profile_ref: skill.budget_profile_ref,
        redaction_posture: skill.redaction_posture,
        reason_codes: grant_reason_codes(skill.skill_ref)
      }
    end)
  end

  defp budgets! do
    {:ok, budget_view} =
      BudgetSurface.view_projection(%{
        budget_ref: "budget://synapse/default",
        period_class: :per_run,
        hard_cap_class: :redacted_above_ceiling,
        soft_cap_class: :bounded_excerpt,
        decision_class: :allow_warn_soft
      })

    {:ok, budget_denial} =
      BudgetSurface.exhaustion_record(%{
        budget_ref: "budget://synapse/effects",
        locus: :runtime_admission,
        decision_class: :deny_policy,
        requested_units: 1,
        granted_units: 0
      })

    {:ok, context_budget} =
      ContextBudgetSurface.view_projection(%{
        budget_ref: context_budget_ref(),
        unit_class: :turn,
        limit_units: 12,
        used_units: 4,
        residual_units: 8
      })

    %{
      run_budget: budget_view,
      denied_effect_budget: budget_denial,
      context_budget: context_budget
    }
  end

  defp costs! do
    {:ok, breakdown} =
      CostSurface.breakdown_projection(%{
        projection_ref: "cost-projection://synapse/catalog",
        tenant_ref: @tenant_ref,
        group_by: :capability_id,
        facts: [
          %{
            fact_ref: "cost-fact://fixture/planner",
            run_ref: "run://fixture/phase-3",
            capability_id: "capability.plan",
            cost_class: :simulation,
            amount_class: :bounded_excerpt,
            token_meter_ref: "token-meter://fixture/planner",
            trace_id: "trace-fixture-catalog"
          }
        ]
      })

    breakdown
  end

  defp eligibility_detail!(item) do
    %{
      item: item,
      model_catalog: model_catalog!(),
      tool_grants: tool_grants!(),
      budgets: budgets!(),
      costs: costs!(),
      assignment_status: assignment_status()
    }
  end

  defp model_profile_attrs do
    [
      %{
        model_profile_ref: "model-profile://synapse/planner",
        provider_ref: "provider://binding/catalog/planner",
        capability_refs: ["capability.plan", "capability.reflect"],
        readiness_ref: "readiness://catalog/ready",
        operation_classes: [:propose, :reflect, :tool_call],
        cost_posture_ref: "cost-posture://bounded",
        source_status: :mock,
        operation_policy_ref: "operation-policy://synapse/planner"
      },
      %{
        model_profile_ref: "model-profile://synapse/summarizer",
        provider_ref: "provider://binding/catalog/summarizer",
        capability_refs: ["capability.summarize", "capability.evaluate"],
        readiness_ref: "readiness://catalog/ready",
        operation_classes: [:summarize, :evaluate],
        cost_posture_ref: "cost-posture://soft-warn",
        source_status: :mock,
        operation_policy_ref: "operation-policy://synapse/summarizer"
      }
    ]
  end

  defp endpoint_profile_attrs do
    [
      %{
        endpoint_profile_ref: "endpoint-profile://synapse/default",
        endpoint_ref: "endpoint://binding/catalog/default",
        endpoint_identity_ref: "endpoint-identity://synapse/default",
        provider_credential_ref: "credential-ref://synapse/default",
        readiness_ref: "readiness://catalog/ready",
        source_status: :mock,
        model_profile_refs: [
          "model-profile://synapse/planner",
          "model-profile://synapse/summarizer"
        ]
      }
    ]
  end

  defp skill_manifest_attrs do
    [
      skill_manifest("skill://synapse/document-summary", "tool://synapse/document-summary",
        capability_ref: "capability://synapse/document-summary",
        capability_id: "capability.summarize"
      ),
      skill_manifest("skill://synapse/external-write", "tool://synapse/external-write",
        capability_ref: "capability://synapse/external-write",
        capability_id: "capability.write.external"
      )
    ]
  end

  defp skill_manifest(skill_ref, tool_ref, opts) do
    capability_ref = Keyword.fetch!(opts, :capability_ref)
    capability_id = Keyword.fetch!(opts, :capability_id)

    %{
      skill_ref: skill_ref,
      version_ref: %{
        skill_ref: skill_ref,
        version_ref: "#{skill_ref}@1",
        revision: 1,
        release_manifest_ref: "release://synapse/catalog"
      },
      tenant_ref: @tenant_ref,
      authority_ref: @authority_ref,
      installation_ref: @installation_ref,
      idempotency_key: "synapse:catalog:#{capability_id}",
      trace_ref: @trace_ref,
      persistence_profile_ref: "persistence://synapse/ref-only",
      release_manifest_ref: "release://synapse/catalog",
      prompt_ref: "prompt://synapse/catalog/#{capability_id}",
      tool_refs: [tool_ref],
      memory_profile_ref: "memory-profile://synapse/default",
      guard_policy_ref: "guard-policy://synapse/default",
      eval_suite_ref: "eval-suite://synapse/catalog",
      budget_profile_ref: "budget-profile://synapse/default",
      conformance_ref: "conformance://synapse/catalog",
      capability_bindings: [
        %{
          binding_ref: "binding://synapse/catalog/#{capability_id}",
          capability_ref: capability_ref,
          connector_ref: "connector://synapse/catalog",
          capability_id: capability_id,
          tenant_ref: @tenant_ref,
          scope_ref: "scope://synapse/default",
          contract_version: "1"
        }
      ],
      composition_refs: []
    }
  end

  defp context_budget_ref do
    %{
      budget_ref: "context-budget://synapse/default",
      tenant_ref: @tenant_ref,
      authority_ref: @authority_ref,
      installation_ref: @installation_ref,
      trace_ref: @trace_ref
    }
  end

  defp grant_status("skill://synapse/external-write"), do: :denied
  defp grant_status(_skill_ref), do: :allowed

  defp grant_reason_codes("skill://synapse/external-write"),
    do: ["effect_write_grant_missing", "operator_review_required"]

  defp grant_reason_codes(_skill_ref), do: []
end
