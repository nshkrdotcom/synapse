defmodule Synapse.ProductPack do
  @moduledoc """
  Product-owned neutral pack definition for the NSHKR Agent workflow.
  """

  @behaviour Mezzanine.Pack

  alias Synapse.{Config, ProductProfile}

  alias Mezzanine.Pack.{
    ContextSourceSpec,
    DecisionSpec,
    EvidenceBinding,
    EvidenceSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    OperationDependency,
    OperationGraph,
    OperationRole,
    OperatorActionSpec,
    ProjectionSpec,
    RuntimeBinding,
    SourceBinding,
    SourceKindSpec,
    SourcePublicationBinding,
    SourcePublishSpec,
    SubjectKindSpec,
    ToolBinding,
    WorkflowSpec
  }

  @subject_kind :agent_work_request
  @source_kind :operator_intake
  @recipe_ref :multi_agent_execution
  @workflow_ref :synapse_agent_workflow
  @graph_ref :synapse_agent_operation_graph
  @placement_ref :platform_default
  @runtime_binding_ref :agent_loop_runtime
  @source_binding_ref :operator_intake_source
  @publication_binding_ref :operator_progress_publication
  @tool_binding_ref :agent_tool_catalog
  @evidence_binding_ref :agent_evidence_stream
  @runtime_manifest_ref "manifest://nshkr/agent/runtime@v1"
  @intake_manifest_ref "manifest://nshkr/product/intake@v1"
  @tool_manifest_ref "manifest://nshkr/agent/tools@v1"
  @evidence_manifest_ref "manifest://nshkr/evidence@v1"
  @binding_manifest_digest "sha256:synapse-neutral-agent-pack-v1"

  @impl true
  def manifest, do: manifest(Config.load())

  @spec manifest(Config.t() | keyword() | map()) :: Manifest.t()
  def manifest(%Config{} = config) do
    %Manifest{
      pack_slug: pack_slug(config),
      version: pack_version(config),
      description: "#{config.product_name} product pack",
      profile_slots: profile_slots(config),
      subject_kind_specs: subject_kind_specs(),
      source_kind_specs: source_kind_specs(),
      binding_specs: binding_specs(),
      source_publish_specs: source_publish_specs(),
      context_source_specs: context_source_specs(),
      lifecycle_specs: lifecycle_specs(),
      execution_recipe_specs: execution_recipe_specs(config),
      operation_graph_specs: operation_graph_specs(),
      workflow_specs: workflow_specs(),
      decision_specs: decision_specs(),
      evidence_specs: evidence_specs(),
      operator_action_specs: operator_action_specs(),
      projection_specs: projection_specs()
    }
  end

  def manifest(overrides), do: overrides |> Config.load() |> manifest()

  @spec pack_slug(Config.t() | keyword() | map()) :: String.t()
  def pack_slug(%Config{} = config), do: config.product_slug
  def pack_slug(overrides), do: overrides |> Config.load() |> pack_slug()

  @spec pack_version(Config.t() | keyword() | map()) :: String.t()
  def pack_version(%Config{} = config), do: config.pack_version
  def pack_version(overrides), do: overrides |> Config.load() |> pack_version()

  @spec runtime_binding_key(Config.t() | keyword() | map()) :: String.t()
  def runtime_binding_key(_config_or_overrides \\ []), do: Atom.to_string(@runtime_binding_ref)

  @spec source_binding_key(Config.t() | keyword() | map()) :: String.t()
  def source_binding_key(_config_or_overrides \\ []), do: Atom.to_string(@source_binding_ref)

  @spec publication_binding_key(Config.t() | keyword() | map()) :: String.t()
  def publication_binding_key(_config_or_overrides \\ []),
    do: Atom.to_string(@publication_binding_ref)

  @spec profile_slots(Config.t() | keyword() | map()) :: map()
  def profile_slots(%Config{}) do
    %{
      source_profile_ref: :operator_intake_v1,
      runtime_profile_ref: :multi_agent_runtime_v1,
      tool_scope_ref: :agent_tools_v1,
      evidence_profile_ref: :agent_evidence_v1,
      publication_profile_ref: :operator_progress_v1,
      review_profile_ref: :human_operator_v1,
      memory_profile_ref: :private_facts_v1,
      projection_profile_ref: :agent_workspace_projection_v1
    }
  end

  def profile_slots(overrides), do: overrides |> Config.load() |> profile_slots()

  defp subject_kind_specs do
    [
      %SubjectKindSpec{
        name: @subject_kind,
        description: "One governed NSHKR Agent work request",
        payload_schema: %{
          identifier: :string,
          title: :string,
          goal: :string,
          risk_class: :string,
          requested_team_template: :string
        }
      }
    ]
  end

  defp source_kind_specs do
    [
      %SourceKindSpec{
        name: @source_kind,
        subject_kind: @subject_kind,
        description: "Operator-submitted product intake"
      }
    ]
  end

  defp binding_specs do
    [
      %SourceBinding{
        binding_ref: @source_binding_ref,
        source_kind: @source_kind,
        subject_kind: @subject_kind,
        connector_ref: :product_intake,
        manifest_ref: @intake_manifest_ref,
        operation_refs: %{
          create_request: "product_intake.request.create",
          list_requests: "product_intake.request.list",
          read_request: "product_intake.request.read"
        },
        credential_binding_ref: :no_credentials_required,
        adapter_ref: :operator_intake,
        connection_ref: :product_session,
        projection_profile_ref: :agent_workspace_projection_v1,
        retry_policy_ref: :product_intake_retry,
        metadata:
          binding_metadata(
            %{
              create_request: :source_write,
              list_requests: :source_read,
              read_request: :source_read
            },
            %{create_request: :write, list_requests: :read, read_request: :read}
          )
      },
      %RuntimeBinding{
        binding_ref: @runtime_binding_ref,
        runtime_family: :workflow,
        connector_ref: :platform_agent_runtime,
        manifest_ref: @runtime_manifest_ref,
        operation_refs: %{
          start_run: "agent.run.start",
          submit_turn: "agent.turn.submit",
          cancel_run: "agent.run.cancel",
          run_status: "agent.run.status"
        },
        credential_binding_ref: :no_credentials_required,
        session_policy_ref: :governed_agent_session,
        tool_catalog_ref: :agent_tools_v1,
        retry_policy_ref: :agent_runtime_retry,
        metadata:
          binding_metadata(
            %{
              start_run: :runtime_operation,
              submit_turn: :runtime_operation,
              cancel_run: :runtime_operation,
              run_status: :runtime_operation
            },
            %{start_run: :write, submit_turn: :write, cancel_run: :write, run_status: :read}
          )
      },
      %ToolBinding{
        binding_ref: @tool_binding_ref,
        runtime_binding_ref: @runtime_binding_ref,
        connector_ref: :platform_tool_router,
        manifest_ref: @tool_manifest_ref,
        operation_refs: %{
          list_available: "agent_tools.list_available",
          invoke_governed: "agent_tools.invoke_governed"
        },
        authorization_class: :runtime_tool_invocation,
        credential_binding_ref: :capability_grant_snapshot,
        tool_schema_ref: :agent_tool_catalog_v1,
        input_policy_ref: :agent_tool_input_policy,
        retry_policy_ref: :agent_tool_retry,
        metadata:
          binding_metadata(
            %{
              list_available: :runtime_tool_invocation,
              invoke_governed: :runtime_tool_invocation
            },
            %{list_available: :read, invoke_governed: :write}
          )
      },
      %SourcePublicationBinding{
        binding_ref: @publication_binding_ref,
        source_binding_ref: @source_binding_ref,
        connector_ref: :product_progress_projection,
        manifest_ref: @intake_manifest_ref,
        operation_refs: %{
          publish_progress: "product_progress.publish",
          publish_decision: "product_progress.decision.publish"
        },
        credential_binding_ref: :no_credentials_required,
        template_ref: :operator_progress_summary,
        publication_profile_ref: :operator_progress_v1,
        retry_policy_ref: :product_publication_retry,
        metadata:
          binding_metadata(
            %{publish_progress: :source_write, publish_decision: :source_write},
            %{publish_progress: :write, publish_decision: :write}
          )
      },
      %EvidenceBinding{
        binding_ref: @evidence_binding_ref,
        evidence_kind: :agent_run_evidence,
        connector_ref: :platform_evidence_stream,
        manifest_ref: @evidence_manifest_ref,
        operation_refs: %{
          record_receipt: "evidence.receipt.record",
          record_review: "evidence.review.record",
          link_replay: "evidence.replay.link"
        },
        credential_binding_ref: :no_credentials_required,
        collection_policy_ref: :agent_evidence_policy,
        retry_policy_ref: :evidence_record_retry,
        metadata:
          binding_metadata(
            %{
              record_receipt: :evidence_collection,
              record_review: :evidence_collection,
              link_replay: :evidence_collection
            },
            %{record_receipt: :write, record_review: :write, link_replay: :write}
          )
      }
    ]
  end

  defp source_publish_specs do
    [
      %SourcePublishSpec{
        publish_ref: :operator_progress_update,
        source_binding_ref: @source_binding_ref,
        trigger: {:execution_completed, @recipe_ref},
        operation: :update_comment,
        template_ref: :operator_progress_summary,
        idempotency_scope: :subject
      }
    ]
  end

  defp context_source_specs do
    [
      %ContextSourceSpec{
        source_ref: :workspace_memory,
        description: "Governed project memory context for agent runs",
        binding_key: :shared_memory,
        usage_phase: :retrieval,
        required?: false,
        timeout_ms: 1_000,
        schema_ref: "context/project_memory",
        max_fragments: 5,
        merge_strategy: :ranked_append
      }
    ]
  end

  defp lifecycle_specs do
    [
      %LifecycleSpec{
        subject_kind: @subject_kind,
        initial_state: :requested,
        terminal_states: [:completed, :rejected, :cancelled, :expired],
        transitions: [
          %{from: :requested, to: :running, trigger: {:execution_requested, @recipe_ref}},
          %{from: :running, to: :awaiting_review, trigger: {:execution_completed, @recipe_ref}},
          %{from: :running, to: :needs_rework, trigger: {:execution_failed, @recipe_ref}},
          %{from: :needs_rework, to: :running, trigger: :auto},
          %{
            from: :awaiting_review,
            to: :completed,
            trigger: {:decision_made, :operator_review, :accept}
          },
          %{
            from: :awaiting_review,
            to: :completed,
            trigger: {:decision_made, :operator_review, :waive}
          },
          %{
            from: :awaiting_review,
            to: :rejected,
            trigger: {:decision_made, :operator_review, :reject}
          },
          %{
            from: :awaiting_review,
            to: :expired,
            trigger: {:decision_made, :operator_review, :expired}
          },
          %{from: :running, to: :cancelled, trigger: {:operator_action, :cancel}}
        ]
      }
    ]
  end

  defp execution_recipe_specs(%Config{} = config) do
    [
      %ExecutionRecipeSpec{
        recipe_ref: @recipe_ref,
        description: "Coordinate a governed multi-agent NSHKR Agent workflow",
        runtime_class: :workflow,
        placement_ref: @placement_ref,
        grant_spec: role_grant_spec(),
        retry_config: %{
          max_attempts: 2,
          backoff: :exponential,
          retry_on: [:transient_failure, :timeout, :infrastructure_error]
        },
        workspace_policy: %{
          strategy: :per_subject,
          reuse: true,
          cleanup: :on_terminal,
          root_ref: :synapse_workspaces
        },
        sandbox_policy_ref: :governed_agent_workspace,
        prompt_refs: Enum.map(ProductProfile.roles(), &Map.fetch!(&1, :prompt_ref)),
        dynamic_tool_manifest: %{
          capability_refs: [
            "agent.context.read",
            "agent.memory.candidate_write",
            "agent.workspace.edit_candidate",
            "agent.evidence.read",
            "agent.review.prepare"
          ]
        },
        hook_stages: [:prepare_context, :after_turn, :before_review],
        max_turns: 16,
        stall_timeout_ms: config.execution_timeout_ms,
        execution_params: %{timeout_ms: config.execution_timeout_ms},
        applicable_to: [@subject_kind]
      }
    ]
  end

  defp operation_graph_specs do
    [
      %OperationGraph{
        graph_ref: @graph_ref,
        workflow_ref: @workflow_ref,
        roles: operation_roles(),
        dependencies: operation_dependencies(),
        joins: [
          %{
            join_ref: :specialist_findings_join,
            waits_for: [
              :implementation_agent_runtime,
              :security_review_agent,
              :performance_review_agent
            ],
            completion_policy: :required,
            failure_policy: :fail_closed
          }
        ],
        metadata: %{
          team_templates: Enum.map(ProductProfile.team_templates(), &Map.fetch!(&1, :ref))
        }
      }
    ]
  end

  defp operation_roles do
    [
      %OperationRole{
        role_ref: :operator_intake,
        binding_ref: @source_binding_ref,
        operation_role: :read_request,
        operation_class: :source_read,
        projection_order_key: 1
      },
      %OperationRole{
        role_ref: :coordinator_agent_runtime,
        binding_ref: @runtime_binding_ref,
        operation_role: :start_run,
        operation_class: :runtime_operation,
        projection_order_key: 2,
        metadata: %{role_ref: :coordinator}
      },
      %OperationRole{
        role_ref: :implementation_agent_runtime,
        binding_ref: @runtime_binding_ref,
        operation_role: :submit_turn,
        operation_class: :runtime_operation,
        projection_order_key: 3,
        metadata: %{role_ref: :implementation_specialist}
      },
      %OperationRole{
        role_ref: :security_review_agent,
        binding_ref: @runtime_binding_ref,
        operation_role: :submit_turn,
        operation_class: :runtime_operation,
        projection_order_key: 4,
        completion_policy: :optional,
        failure_policy: :degrade,
        metadata: %{role_ref: :security_specialist}
      },
      %OperationRole{
        role_ref: :performance_review_agent,
        binding_ref: @runtime_binding_ref,
        operation_role: :submit_turn,
        operation_class: :runtime_operation,
        projection_order_key: 5,
        completion_policy: :optional,
        failure_policy: :degrade,
        metadata: %{role_ref: :performance_specialist}
      },
      %OperationRole{
        role_ref: :tool_catalog,
        binding_ref: @tool_binding_ref,
        operation_role: :list_available,
        operation_class: :runtime_tool_invocation,
        projection_order_key: 6,
        completion_policy: :optional,
        failure_policy: :degrade
      },
      %OperationRole{
        role_ref: :agent_evidence,
        binding_ref: @evidence_binding_ref,
        operation_role: :record_receipt,
        operation_class: :evidence_collection,
        projection_order_key: 7
      },
      %OperationRole{
        role_ref: :operator_progress,
        binding_ref: @publication_binding_ref,
        operation_role: :publish_progress,
        operation_class: :source_write,
        projection_order_key: 8
      }
    ]
  end

  defp operation_dependencies do
    [
      %OperationDependency{
        from_role: :operator_intake,
        to_role: :coordinator_agent_runtime,
        relation: :blocks_on_success
      },
      %OperationDependency{
        from_role: :coordinator_agent_runtime,
        to_role: :implementation_agent_runtime,
        relation: :blocks_on_success
      },
      %OperationDependency{
        from_role: :implementation_agent_runtime,
        to_role: :security_review_agent,
        relation: :parallel_allowed,
        completion_policy: :optional,
        failure_policy: :degrade
      },
      %OperationDependency{
        from_role: :implementation_agent_runtime,
        to_role: :performance_review_agent,
        relation: :parallel_allowed,
        completion_policy: :optional,
        failure_policy: :degrade
      },
      %OperationDependency{
        from_role: :implementation_agent_runtime,
        to_role: :agent_evidence,
        relation: :blocks_on_success
      },
      %OperationDependency{
        from_role: :agent_evidence,
        to_role: :operator_progress,
        relation: :blocks_on_review,
        review_policy_ref: :operator_review
      }
    ]
  end

  defp workflow_specs do
    [
      %WorkflowSpec{
        workflow_ref: @workflow_ref,
        source_role_ref: :operator_intake,
        runtime_role_ref: :coordinator_agent_runtime,
        publication_role_ref: :operator_progress,
        evidence_role_refs: [:agent_evidence],
        operation_graph_ref: @graph_ref,
        metadata: %{
          runtime_member_role_refs: [
            :implementation_agent_runtime,
            :security_review_agent,
            :performance_review_agent
          ],
          tool_role_refs: [:tool_catalog]
        }
      }
    ]
  end

  defp decision_specs do
    [
      %DecisionSpec{
        decision_kind: :operator_review,
        description: "Operator review gate before external effects or durable learning",
        trigger: {:after_execution_completed, @recipe_ref},
        required_evidence_kinds: [:run_receipt, :decision_record],
        authorized_actors: [:operator],
        allowed_decisions: [:accept, :reject, :waive, :expired, :escalate],
        required_within_hours: 72
      },
      %DecisionSpec{
        decision_kind: :memory_promotion_review,
        description: "Review candidate memory before durable promotion",
        trigger: {:after_decision, :operator_review, :accept},
        required_evidence_kinds: [:memory_candidate],
        authorized_actors: [:operator],
        allowed_decisions: [:accept, :reject, :waive],
        required_within_hours: 168
      }
    ]
  end

  defp evidence_specs do
    [
      %EvidenceSpec{
        evidence_kind: :run_receipt,
        description: "Product-safe run receipt summary",
        collector_ref: :agent_evidence_stream,
        collection_strategy: :automatic,
        collected_on: {:execution_completed, @recipe_ref},
        schema: %{run_ref: :string, status: :string, receipt_ref: :string}
      },
      %EvidenceSpec{
        evidence_kind: :context_pack,
        description: "Context pack refs used by the run",
        collector_ref: :context_pack_projection,
        collection_strategy: :automatic,
        collected_on: {:execution_completed, @recipe_ref},
        schema: %{context_pack_ref: :string, redaction_profile: :string}
      },
      %EvidenceSpec{
        evidence_kind: :decision_record,
        description: "Authority-backed operator decision record",
        collector_ref: :review_projection,
        collection_strategy: :automatic,
        collected_on: {:decision_created, :operator_review},
        schema: %{decision_ref: :string, decision: :string}
      },
      %EvidenceSpec{
        evidence_kind: :memory_candidate,
        description: "Candidate memory refs produced by the agent workflow",
        collector_ref: :memory_candidate_projection,
        collection_strategy: :on_demand,
        collected_on: {:subject_entered_state, :awaiting_review},
        schema: %{candidate_ref: :string, state: :string}
      }
    ]
  end

  defp operator_action_specs do
    [
      %OperatorActionSpec{
        action_kind: :pause,
        description: "Pause the active agent run",
        applicable_states: [:running, :awaiting_review],
        authorized_roles: [:operator],
        effect: :pause_execution
      },
      %OperatorActionSpec{
        action_kind: :resume,
        description: "Resume a paused agent run",
        applicable_states: [:running],
        authorized_roles: [:operator],
        effect: :resume_execution
      },
      %OperatorActionSpec{
        action_kind: :retry,
        description: "Retry a failed agent run",
        applicable_states: [:needs_rework],
        authorized_roles: [:operator],
        effect: :retry_execution
      },
      %OperatorActionSpec{
        action_kind: :cancel,
        description: "Cancel the active agent run",
        applicable_states: [:requested, :running, :needs_rework],
        authorized_roles: [:operator],
        effect: :cancel_active_execution
      }
    ]
  end

  defp projection_specs do
    [
      %ProjectionSpec{
        name: :run_queue,
        description: "Operator run queue for Synapse agent work",
        subject_kinds: [@subject_kind],
        default_filters: %{lifecycle_state: [:requested, :running, :awaiting_review]},
        sort: [{:updated_at, :desc}],
        included_fields: [:subject_kind, :lifecycle_state, :team_template_ref, :risk_class]
      },
      %ProjectionSpec{
        name: :review_queue,
        description: "Operator review queue for pending agent decisions",
        subject_kinds: [@subject_kind],
        default_filters: %{lifecycle_state: :awaiting_review},
        sort: [{:inserted_at, :asc}],
        included_fields: [:subject_kind, :lifecycle_state, :evidence_refs]
      },
      %ProjectionSpec{
        name: :evidence_timeline,
        description: "Receipt, review, and replay refs for a run",
        subject_kinds: [@subject_kind],
        default_filters: %{},
        sort: [{:event_seq, :asc}],
        included_fields: :all
      }
    ]
  end

  defp role_grant_spec do
    ProductProfile.roles()
    |> Map.new(fn role ->
      {Map.fetch!(role, :ref),
       %{
         budget_class: Map.fetch!(role, :budget_class),
         tool_capability_refs: Map.fetch!(role, :tool_capability_refs),
         memory_read_grant_refs: Map.fetch!(role, :memory_read_grant_refs),
         memory_write_grant_refs: Map.fetch!(role, :memory_write_grant_refs),
         failure_posture: Map.fetch!(role, :failure_posture)
       }}
    end)
  end

  defp binding_metadata(operation_classes, side_effect_classes) do
    %{
      manifest_digest: @binding_manifest_digest,
      operation_classes: operation_classes,
      side_effect_classes: side_effect_classes,
      required_scopes: %{}
    }
  end
end
