# Synapse Orchestrator Configuration Examples

**Real-world agent configuration patterns and examples**

## Overview

This guide provides complete, working examples of agent configurations for various use cases. Each example is production-ready and demonstrates best practices.

## Table of Contents

1. [Basic Specialist Agent](#basic-specialist-agent)
2. [Advanced Specialist with State](#advanced-specialist-with-state)
3. [Simple Orchestrator](#simple-orchestrator)
4. [Complex Multi-Stage Orchestrator](#complex-multi-stage-orchestrator)
5. [Conditional Agents](#conditional-agents)
6. [Agent Templates](#agent-templates)
7. [Multi-Domain System](#multi-domain-system)
8. [Custom Behavior Agents](#custom-behavior-agents)

---

## Basic Specialist Agent

**Use Case**: Simple action executor

```elixir
# config/agents/simple_specialist.exs
[
  %{
    id: :email_validator,
    type: :specialist,

    # Single action
    actions: [
      MyApp.Actions.ValidateEmail
    ],

    # Simple signal routing
    signals: %{
      subscribes: ["email.validate"],
      emits: ["email.validated"]
    }
  }
]
```

**Behavior**:
1. Subscribe to `"email.validate"` signals
2. Execute `ValidateEmail` action
3. Emit `"email.validated"` signal with results

**Result Format** (auto-generated):
```elixir
%{
  agent: "email_validator",
  confidence: 0.95,
  findings: [...],
  metadata: %{actions_run: [ValidateEmail]}
}
```

---

## Advanced Specialist with State

**Use Case**: Specialist that learns from history

```elixir
# config/agents/learning_specialist.exs
[
  %{
    id: :security_specialist,
    type: :specialist,

    # Multiple security actions
    actions: [
      Synapse.Actions.Security.CheckSQLInjection,
      Synapse.Actions.Security.CheckXSS,
      Synapse.Actions.Security.CheckAuthIssues
    ],

    signals: %{
      subscribes: ["review.request", "review.recheck"],
      emits: ["review.result", "security.alert"]
    },

    # Custom result builder
    result_builder: fn action_results, review_id ->
      all_findings = Enum.flat_map(action_results, fn
        {:ok, result} -> Map.get(result, :findings, [])
        {:error, _} -> []
      end)

      # Calculate confidence based on pattern recognition
      avg_confidence = calculate_confidence(action_results)

      %{
        review_id: review_id,
        agent: "security_specialist",
        confidence: avg_confidence,
        findings: all_findings,
        should_escalate: Enum.any?(all_findings, &(&1.severity == :high)),
        metadata: %{
          runtime_ms: 0,  # Filled by framework
          path: :deep_review,
          actions_run: [CheckSQLInjection, CheckXSS, CheckAuthIssues],
          pattern_matches: count_pattern_matches(all_findings)
        }
      }
    end,

    # Stateful learning
    state_schema: [
      review_history: [
        type: {:list, :map},
        default: [],
        doc: "Last 100 reviews with outcomes"
      ],
      learned_patterns: [
        type: {:list, :map},
        default: [],
        doc: "Recognized vulnerability patterns"
      ],
      scar_tissue: [
        type: {:list, :map},
        default: [],
        doc: "False positive patterns to avoid"
      ],
      total_reviews: [
        type: :integer,
        default: 0
      ],
      total_findings: [
        type: :integer,
        default: 0
      ]
    ],

    metadata: %{
      owner: "security-team@company.com",
      sla_ms: 100,
      criticality: :high,
      cost_per_review: 0.05
    }
  }
]
```

---

## Simple Orchestrator

**Use Case**: Basic multi-agent coordination

```elixir
# config/agents/simple_orchestrator.exs
[
  # Two specialists
  %{
    id: :validator,
    type: :specialist,
    actions: [ValidateData],
    signals: %{subscribes: ["data.input"], emits: ["data.validated"]}
  },

  %{
    id: :processor,
    type: :specialist,
    actions: [ProcessData],
    signals: %{subscribes: ["data.validated"], emits: ["data.processed"]}
  },

  # Simple orchestrator
  %{
    id: :data_coordinator,
    type: :orchestrator,

    actions: [
      MyApp.Actions.ClassifyData,
      MyApp.Actions.AggregateResults
    ],

    signals: %{
      subscribes: ["data.input", "data.processed"],
      emits: ["data.complete"]
    },

    orchestration: %{
      # Simple classification
      classify_fn: fn data ->
        if data.size > 1000 do
          %{path: :deep_review, rationale: "Large dataset"}
        else
          %{path: :fast_path, rationale: "Small dataset"}
        end
      end,

      # Spawn both specialists
      spawn_specialists: [:validator, :processor],

      # Simple aggregation
      aggregation_fn: fn results, state ->
        %{
          data_id: state.data_id,
          status: :complete,
          results: results
        }
      end
    },

    state_schema: [
      processed_count: [type: :integer, default: 0]
    ]
  }
]
```

---

## Complex Multi-Stage Orchestrator

**Use Case**: Multi-stage review with parallel specialists

```elixir
# config/agents/code_review_system.exs
alias Synapse.Orchestrator.Behaviors

[
  # Stage 1: Specialist Agents (run in parallel)

  %{
    id: :security_specialist,
    type: :specialist,
    actions: [CheckSQLInjection, CheckXSS, CheckAuthIssues, CheckCrypto],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    result_builder: &Behaviors.build_security_result/2,
    metadata: %{stage: 1, domain: :security}
  },

  %{
    id: :performance_specialist,
    type: :specialist,
    actions: [CheckComplexity, CheckMemory, ProfileHotPath, CheckNPlusOne],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    result_builder: &Behaviors.build_performance_result/2,
    metadata: %{stage: 1, domain: :performance}
  },

  %{
    id: :quality_specialist,
    type: :specialist,
    actions: [CheckTestCoverage, CheckDocumentation, CheckCodeStyle],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    result_builder: &Behaviors.build_quality_result/2,
    metadata: %{stage: 1, domain: :quality}
  },

  # Stage 2: Primary Coordinator (spawns stage 1 specialists)

  %{
    id: :primary_coordinator,
    type: :orchestrator,

    actions: [
      Synapse.Actions.Review.ClassifyChange,
      Synapse.Actions.Review.GenerateSummary
    ],

    signals: %{
      subscribes: ["review.request", "review.result"],
      emits: ["review.summary"]
    },

    orchestration: %{
      # Smart classification based on multiple factors
      classify_fn: fn review_data ->
        cond do
          review_data.files_changed > 100 ->
            %{path: :deep_review, rationale: "Very large change (#{review_data.files_changed} files)"}

          "breaking" in review_data.labels ->
            %{path: :deep_review, rationale: "Breaking change requires full review"}

          critical_files_changed?(review_data.metadata.files) ->
            %{path: :deep_review, rationale: "Critical files modified"}

          review_data.intent == "hotfix" and review_data.files_changed < 5 ->
            %{path: :fast_path, rationale: "Small hotfix"}

          review_data.risk_factor > 0.7 ->
            %{path: :deep_review, rationale: "High risk factor: #{review_data.risk_factor}"}

          true ->
            %{path: :fast_path, rationale: "Standard review"}
        end
      end,

      # Dynamic specialist spawning based on labels
      spawn_specialists: fn review_data ->
        base = [:security_specialist]

        specialists = if "performance" in review_data.labels do
          [:performance_specialist | base]
        else
          base
        end

        specialists = if "quality" in review_data.labels do
          [:quality_specialist | specialists]
        else
          specialists
        end

        specialists
      end,

      # Sophisticated aggregation
      aggregation_fn: fn specialist_results, review_state ->
        all_findings = Enum.flat_map(specialist_results, & &1.findings)

        # Group findings by domain
        findings_by_domain = Enum.group_by(all_findings, fn finding ->
          specialist = Enum.find(specialist_results, fn r ->
            finding in r.findings
          end)
          specialist.metadata.domain
        end)

        %{
          review_id: review_state.review_id,
          status: :complete,
          severity: calculate_max_severity(all_findings),
          findings: all_findings,
          findings_by_domain: findings_by_domain,
          recommendations: extract_recommendations(all_findings),
          escalations: generate_escalations(all_findings),
          metadata: %{
            decision_path: review_state.classification_path,
            specialists_resolved: Enum.map(specialist_results, & &1.agent),
            duration_ms: calculate_duration(review_state),
            specialist_breakdown: specialist_breakdown(specialist_results)
          }
        }
      end,

      # Fast path optimization
      fast_path_fn: fn signal, bus ->
        # Emit summary immediately for trivial changes
        summary = %{
          review_id: signal.data.review_id,
          status: :complete,
          severity: :none,
          findings: [],
          recommendations: [],
          escalations: [],
          metadata: %{
            decision_path: :fast_path,
            specialists_resolved: [],
            duration_ms: 0,
            skipped_reason: "Small, low-risk change"
          }
        }

        {:ok, summary_signal} = Jido.Signal.new(%{
          type: "review.summary",
          source: "/synapse/agents/primary_coordinator",
          subject: "jido://review/#{signal.data.review_id}",
          data: summary
        })

        Jido.Signal.Bus.publish(bus, [summary_signal])
      end
    },

    state_schema: [
      review_count: [type: :integer, default: 0],
      active_reviews: [type: :map, default: %{}],
      fast_path_count: [type: :integer, default: 0],
      deep_review_count: [type: :integer, default: 0],
      specialists_spawned: [type: :integer, default: 0]
    ],

    depends_on: [:security_specialist, :performance_specialist, :quality_specialist]
  }
]
```

---

## Conditional Agents

**Use Case**: Feature flags and environment-specific agents

```elixir
# config/agents/conditional.exs
[
  # Always present - core functionality
  %{
    id: :core_security,
    type: :specialist,
    actions: [CheckSQL, CheckXSS],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]}
  },

  # Premium feature - only in production with flag
  %{
    id: :advanced_security,
    type: :specialist,

    actions: [
      MyApp.Actions.Security.AdvancedThreatDetection,
      MyApp.Actions.Security.ZeroDayScanner,
      MyApp.Actions.Security.MLVulnerabilityDetection
    ],

    signals: %{
      subscribes: ["review.request"],
      emits: ["security.advanced_result"]
    },

    spawn_condition: fn ->
      Application.get_env(:synapse, :environment) == :production and
      Application.get_env(:synapse, :premium_features, false)
    end,

    metadata: %{
      tier: :premium,
      cost_per_review: 0.50
    }
  },

  # Development-only agent
  %{
    id: :debug_logger,
    type: :specialist,

    actions: [MyApp.Actions.LogDebugInfo],

    signals: %{
      subscribes: ["review.**"],  # All review signals
      emits: ["debug.logged"]
    },

    spawn_condition: fn ->
      Application.get_env(:synapse, :environment) == :development
    end
  },

  # Regional compliance agent
  %{
    id: :gdpr_compliance,
    type: :specialist,

    actions: [
      MyApp.Actions.Compliance.CheckGDPR,
      MyApp.Actions.Compliance.CheckDataRetention
    ],

    signals: %{
      subscribes: ["review.request"],
      emits: ["compliance.result"]
    },

    spawn_condition: fn ->
      :eu in Application.get_env(:synapse, :active_regions, [])
    end,

    metadata: %{
      region: :eu,
      regulation: :gdpr
    }
  }
]
```

---

## Agent Templates

**Use Case**: Reusable configuration patterns

```elixir
# lib/my_app/agent_templates.ex
defmodule MyApp.AgentTemplates do
  @moduledoc """
  Reusable agent configuration templates.
  """

  alias Synapse.Orchestrator.Behaviors

  @doc "Standard specialist template"
  def specialist_template(overrides \\ %{}) do
    base = %{
      type: :specialist,

      signals: %{
        subscribes: ["review.request"],
        emits: ["review.result"]
      },

      result_builder: &Behaviors.build_specialist_result/3,

      state_schema: [
        review_history: [type: {:list, :map}, default: []],
        learned_patterns: [type: {:list, :map}, default: []],
        total_reviews: [type: :integer, default: 0]
      ],

      bus: :synapse_bus,
      registry: :synapse_registry
    }

    Map.merge(base, overrides)
  end

  @doc "Creates security specialist from template"
  def security_specialist(actions) do
    specialist_template(%{
      id: :security_specialist,
      actions: actions,
      metadata: %{
        domain: :security,
        owner: "security-team",
        sla_ms: 100
      }
    })
  end

  @doc "Creates performance specialist from template"
  def performance_specialist(actions) do
    specialist_template(%{
      id: :performance_specialist,
      actions: actions,
      metadata: %{
        domain: :performance,
        owner: "performance-team",
        sla_ms: 150
      }
    })
  end

  @doc "Creates custom specialist with specific config"
  def custom_specialist(id, actions, opts \\ []) do
    overrides = %{
      id: id,
      actions: actions,
      metadata: Keyword.get(opts, :metadata, %{}),
      state_schema: Keyword.get(opts, :state_schema, [])
    }

    specialist_template(overrides)
  end

  @doc "Standard orchestrator template"
  def orchestrator_template(overrides \\ %{}) do
    base = %{
      type: :orchestrator,

      actions: [
        Synapse.Actions.Review.ClassifyChange,
        Synapse.Actions.Review.GenerateSummary
      ],

      signals: %{
        subscribes: ["review.request", "review.result"],
        emits: ["review.summary"]
      },

      orchestration: %{
        classify_fn: &Behaviors.classify_review/1,
        aggregation_fn: &Behaviors.aggregate_results/2
      },

      state_schema: [
        review_count: [type: :integer, default: 0],
        active_reviews: [type: :map, default: %{}]
      ]
    }

    Map.merge(base, overrides)
  end
end

# config/agents.exs - Using templates
alias MyApp.AgentTemplates

[
  # Create agents from templates
  AgentTemplates.security_specialist([
    Synapse.Actions.Security.CheckSQLInjection,
    Synapse.Actions.Security.CheckXSS,
    Synapse.Actions.Security.CheckAuthIssues
  ]),

  AgentTemplates.performance_specialist([
    Synapse.Actions.Performance.CheckComplexity,
    Synapse.Actions.Performance.CheckMemoryUsage
  ]),

  AgentTemplates.orchestrator_template(%{
    id: :coordinator,
    orchestration: %{
      classify_fn: &Behaviors.classify_review/1,
      spawn_specialists: [:security_specialist, :performance_specialist],
      aggregation_fn: &Behaviors.aggregate_results/2
    }
  })
]
```

---

## Multi-Domain System

**Use Case**: Complete multi-domain review system

```elixir
# config/agents/multi_domain.exs
alias Synapse.Orchestrator.Behaviors

[
  # Domain 1: Security
  %{
    id: :security_static,
    type: :specialist,
    actions: [CheckSQL, CheckXSS, CheckAuth, CheckCrypto],
    signals: %{subscribes: ["review.request"], emits: ["security.static_result"]},
    metadata: %{domain: :security, stage: :static_analysis}
  },

  %{
    id: :security_dynamic,
    type: :specialist,
    actions: [DynamicTaintAnalysis, FuzzTesting],
    signals: %{subscribes: ["review.request"], emits: ["security.dynamic_result"]},
    metadata: %{domain: :security, stage: :dynamic_analysis}
  },

  # Domain 2: Performance
  %{
    id: :performance_static,
    type: :specialist,
    actions: [CheckComplexity, CheckMemoryPatterns, CheckAlgorithms],
    signals: %{subscribes: ["review.request"], emits: ["performance.static_result"]},
    metadata: %{domain: :performance, stage: :static_analysis}
  },

  %{
    id: :performance_profiler,
    type: :specialist,
    actions: [ProfileExecution, BenchmarkChanges],
    signals: %{subscribes: ["review.request"], emits: ["performance.profile_result"]},
    metadata: %{domain: :performance, stage: :profiling}
  },

  # Domain 3: Quality
  %{
    id: :quality_checker,
    type: :specialist,
    actions: [CheckTests, CheckDocs, CheckCodeStyle, CheckDuplication],
    signals: %{subscribes: ["review.request"], emits: ["quality.result"]},
    metadata: %{domain: :quality}
  },

  # Domain 4: Compliance
  %{
    id: :compliance_checker,
    type: :specialist,
    actions: [CheckLicenses, CheckDependencies, CheckGDPR, CheckSOC2],
    signals: %{subscribes: ["review.request"], emits: ["compliance.result"]},
    metadata: %{domain: :compliance}
  },

  # Domain Coordinators (one per domain)

  %{
    id: :security_coordinator,
    type: :orchestrator,
    actions: [AggregateSecurityFindings],
    signals: %{
      subscribes: ["security.static_result", "security.dynamic_result"],
      emits: ["security.summary"]
    },
    orchestration: %{
      classify_fn: fn _ -> %{path: :deep_review, rationale: "Always deep"} end,
      spawn_specialists: [:security_static, :security_dynamic],
      aggregation_fn: &aggregate_security_results/2
    },
    metadata: %{coordinator_type: :domain}
  },

  %{
    id: :performance_coordinator,
    type: :orchestrator,
    actions: [AggregatePerformanceFindings],
    signals: %{
      subscribes: ["performance.static_result", "performance.profile_result"],
      emits: ["performance.summary"]
    },
    orchestration: %{
      classify_fn: fn _ -> %{path: :deep_review, rationale: "Always deep"} end,
      spawn_specialists: [:performance_static, :performance_profiler],
      aggregation_fn: &aggregate_performance_results/2
    },
    metadata: %{coordinator_type: :domain}
  },

  # Master Coordinator (aggregates all domains)

  %{
    id: :master_coordinator,
    type: :orchestrator,

    actions: [
      Synapse.Actions.Review.ClassifyChange,
      Synapse.Actions.Review.GenerateFinalSummary
    ],

    signals: %{
      subscribes: [
        "review.request",
        "security.summary",
        "performance.summary",
        "quality.result",
        "compliance.result"
      ],
      emits: ["review.final_summary"]
    },

    orchestration: %{
      # Top-level classification
      classify_fn: &Behaviors.classify_review/1,

      # Spawn domain coordinators and direct specialists
      spawn_specialists: [
        :security_coordinator,
        :performance_coordinator,
        :quality_checker,
        :compliance_checker
      ],

      # Master aggregation across all domains
      aggregation_fn: fn all_results, review_state ->
        # Separate domain summaries from specialist results
        domain_summaries = Enum.filter(all_results, &(&1.metadata[:coordinator_type] == :domain))
        direct_results = Enum.filter(all_results, &(&1.metadata[:coordinator_type] != :domain))

        all_findings =
          Enum.flat_map(domain_summaries, & &1.findings) ++
          Enum.flat_map(direct_results, & &1.findings)

        %{
          review_id: review_state.review_id,
          status: :complete,
          severity: calculate_max_severity(all_findings),
          findings: all_findings,
          domain_breakdown: %{
            security: extract_domain_findings(all_findings, :security),
            performance: extract_domain_findings(all_findings, :performance),
            quality: extract_domain_findings(all_findings, :quality),
            compliance: extract_domain_findings(all_findings, :compliance)
          },
          recommendations: extract_recommendations(all_findings),
          metadata: %{
            decision_path: review_state.classification_path,
            specialists_resolved: Enum.map(all_results, & &1.agent),
            duration_ms: calculate_duration(review_state),
            domains_analyzed: [:security, :performance, :quality, :compliance]
          }
        }
      end
    },

    state_schema: [
      review_count: [type: :integer, default: 0],
      active_reviews: [type: :map, default: %{}],
      domain_stats: [type: :map, default: %{}]
    ],

    depends_on: [
      :security_coordinator,
      :performance_coordinator,
      :quality_checker,
      :compliance_checker
    ],

    metadata: %{
      coordinator_type: :master,
      owner: "platform-team"
    }
  }
]
```

**System Topology**:
```
review.request
  ↓
master_coordinator (classifies)
  ↓
Spawns 4 specialists:
  ├─> security_coordinator
  │     ├─> security_static
  │     └─> security_dynamic
  ├─> performance_coordinator
  │     ├─> performance_static
  │     └─> performance_profiler
  ├─> quality_checker
  └─> compliance_checker
  ↓
Aggregates 4 results
  ↓
review.final_summary
```

---

## Custom Behavior Agents

**Use Case**: Agents with unique, non-standard behavior

```elixir
# config/agents/custom.exs
[
  # Custom agent with manual signal handling
  %{
    id: :custom_processor,
    type: :custom,

    # Custom handler instead of standard specialist pattern
    custom_handler: fn signal, state ->
      case signal.type do
        "custom.event" ->
          # Custom processing logic
          result = process_custom_event(signal.data)

          # Emit custom signal
          {:ok, custom_signal} = Jido.Signal.new(%{
            type: "custom.processed",
            source: "/custom/processor",
            data: result
          })

          Jido.Signal.Bus.publish(:synapse_bus, [custom_signal])

          # Update state
          updated_state = Map.update(state, :processed_count, 1, &(&1 + 1))
          {:ok, updated_state}

        _ ->
          {:ok, state}
      end
    end,

    signals: %{
      subscribes: ["custom.**"],
      emits: ["custom.processed"]
    },

    state_schema: [
      processed_count: [type: :integer, default: 0],
      last_event: [type: :map, default: %{}]
    ]
  },

  # Aggregator with custom logic
  %{
    id: :metrics_aggregator,
    type: :custom,

    custom_handler: fn signal, state ->
      # Collect metrics from various sources
      metrics = extract_metrics(signal)

      # Update rolling window
      updated_window = update_metrics_window(state.metrics_window, metrics)

      # Emit aggregated metrics every 100 signals
      new_count = state.signal_count + 1

      if rem(new_count, 100) == 0 do
        aggregate = calculate_aggregate(updated_window)
        emit_metrics_signal(aggregate)
      end

      {:ok, %{state |
        metrics_window: updated_window,
        signal_count: new_count
      }}
    end,

    signals: %{
      subscribes: ["metrics.**"],
      emits: ["metrics.aggregate"]
    },

    state_schema: [
      metrics_window: [type: {:list, :map}, default: []],
      signal_count: [type: :integer, default: 0]
    ]
  }
]
```

---

## Data Pipeline System

**Use Case**: ETL-style data processing pipeline

```elixir
# config/agents/data_pipeline.exs
[
  # Stage 1: Extraction
  %{
    id: :data_extractor,
    type: :specialist,
    actions: [
      MyApp.Actions.ExtractFromDatabase,
      MyApp.Actions.ExtractFromAPI,
      MyApp.Actions.ExtractFromFiles
    ],
    signals: %{
      subscribes: ["pipeline.start"],
      emits: ["pipeline.extracted"]
    }
  },

  # Stage 2: Validation
  %{
    id: :data_validator,
    type: :specialist,
    actions: [
      MyApp.Actions.ValidateSchema,
      MyApp.Actions.ValidateIntegrity,
      MyApp.Actions.ValidateBusinessRules
    ],
    signals: %{
      subscribes: ["pipeline.extracted"],
      emits: ["pipeline.validated"]
    }
  },

  # Stage 3: Transformation (parallel)
  %{
    id: :data_transformer_a,
    type: :specialist,
    actions: [MyApp.Actions.TransformTypeA],
    signals: %{subscribes: ["pipeline.validated"], emits: ["pipeline.transformed_a"]}
  },

  %{
    id: :data_transformer_b,
    type: :specialist,
    actions: [MyApp.Actions.TransformTypeB],
    signals: %{subscribes: ["pipeline.validated"], emits: ["pipeline.transformed_b"]}
  },

  # Stage 4: Enrichment
  %{
    id: :data_enricher,
    type: :specialist,
    actions: [
      MyApp.Actions.EnrichWithMetadata,
      MyApp.Actions.EnrichWithExternalData
    ],
    signals: %{
      subscribes: ["pipeline.transformed_a", "pipeline.transformed_b"],
      emits: ["pipeline.enriched"]
    }
  },

  # Stage 5: Loading
  %{
    id: :data_loader,
    type: :specialist,
    actions: [
      MyApp.Actions.LoadToWarehouse,
      MyApp.Actions.UpdateIndexes,
      MyApp.Actions.NotifyDownstream
    ],
    signals: %{
      subscribes: ["pipeline.enriched"],
      emits: ["pipeline.complete"]
    }
  },

  # Pipeline Coordinator
  %{
    id: :pipeline_coordinator,
    type: :orchestrator,

    actions: [MyApp.Actions.ClassifyPipeline, MyApp.Actions.GeneratePipelineReport],

    signals: %{
      subscribes: ["pipeline.start", "pipeline.complete"],
      emits: ["pipeline.report"]
    },

    orchestration: %{
      classify_fn: fn data ->
        if data.size > 1_000_000 do
          %{path: :deep_review, rationale: "Large dataset"}
        else
          %{path: :fast_path, rationale: "Small dataset"}
        end
      end,

      spawn_specialists: [
        :data_extractor,
        :data_validator,
        :data_transformer_a,
        :data_transformer_b,
        :data_enricher,
        :data_loader
      ],

      aggregation_fn: fn results, state ->
        %{
          pipeline_id: state.pipeline_id,
          status: :complete,
          stages_completed: length(results),
          total_duration_ms: calculate_duration(state)
        }
      end
    },

    state_schema: [
      pipeline_count: [type: :integer, default: 0],
      active_pipelines: [type: :map, default: %{}]
    ]
  }
]
```

---

## Environment-Specific Configurations

**Use Case**: Different agent sets per environment

```elixir
# config/agents/common.exs
defmodule MyApp.CommonAgents do
  def base_agents do
    [
      %{
        id: :core_security,
        type: :specialist,
        actions: [CheckSQL, CheckXSS],
        signals: %{subscribes: ["review.request"], emits: ["review.result"]}
      },
      %{
        id: :basic_coordinator,
        type: :orchestrator,
        orchestration: %{
          classify_fn: &simple_classify/1,
          spawn_specialists: [:core_security],
          aggregation_fn: &simple_aggregate/2
        },
        signals: %{subscribes: ["review.request", "review.result"], emits: ["review.summary"]}
      }
    ]
  end
end

# config/agents/dev.exs
import MyApp.CommonAgents

base_agents() ++ [
  # Additional dev-only agents
  %{
    id: :debug_logger,
    type: :specialist,
    actions: [LogAllSignals],
    signals: %{subscribes: ["**"], emits: ["debug.logged"]},
    metadata: %{env: :development}
  }
]

# config/agents/staging.exs
import MyApp.CommonAgents

base_agents() ++ [
  # Staging-specific testing agents
  %{
    id: :performance_profiler,
    type: :specialist,
    actions: [ProfilePerformance],
    signals: %{subscribes: ["review.request"], emits: ["performance.profile"]},
    metadata: %{env: :staging}
  }
]

# config/agents/prod.exs
import MyApp.CommonAgents

base_agents() ++ [
  # Production - all specialists
  %{
    id: :security_advanced,
    type: :specialist,
    actions: [CheckSQL, CheckXSS, CheckAuth, CheckCrypto, MLThreatDetection],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    metadata: %{env: :production, tier: :premium}
  },
  %{
    id: :performance_advanced,
    type: :specialist,
    actions: [CheckComplexity, CheckMemory, ProfileHotPath, BenchmarkRegression],
    signals: %{subscribes: ["review.request"], emits: ["review.result"]},
    metadata: %{env: :production, tier: :premium}
  },
  %{
    id: :compliance_full,
    type: :specialist,
    actions: [CheckGDPR, CheckSOC2, CheckHIPAA, CheckPCI],
    signals: %{subscribes: ["review.request"], emits: ["compliance.result"]},
    metadata: %{env: :production}
  }
]
```

**Application startup**:

```elixir
def start(_type, _args) do
  # Load environment-specific config
  config_file = "config/agents/#{Application.get_env(:synapse, :environment, :dev)}.exs"

  children = [
    {Jido.Signal.Bus, name: :synapse_bus},
    {Synapse.Orchestrator.Runtime, config_source: config_file}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

---

## Testing Configurations

**Use Case**: Minimal configs for testing

```elixir
# test/fixtures/test_agents.exs
[
  # Minimal echo agent for testing
  %{
    id: :test_echo,
    type: :specialist,
    actions: [Synapse.Actions.Echo],
    signals: %{subscribes: ["test.input"], emits: ["test.output"]},
    metadata: %{test: true}
  },

  # Failing agent for error testing
  %{
    id: :test_failing,
    type: :specialist,
    actions: [MyApp.Actions.TestFailingAction],
    signals: %{subscribes: ["test.fail"], emits: ["test.failed"]},
    metadata: %{test: true}
  },

  # Slow agent for timeout testing
  %{
    id: :test_slow,
    type: :specialist,
    actions: [MyApp.Actions.TestSlowAction],
    signals: %{subscribes: ["test.slow"], emits: ["test.completed"]},
    metadata: %{test: true}
  }
]
```

---

## Best Practices

### 1. Organization

```elixir
# Good - organized by domain
config/agents/
├── security/
│   ├── specialists.exs
│   └── coordinator.exs
├── performance/
│   ├── specialists.exs
│   └── coordinator.exs
└── main_coordinator.exs

# config/agents.exs - main entry point
import_file "config/agents/**/*.exs"
|> List.flatten()
```

### 2. Reusability

```elixir
# Good - extract common patterns
defmodule MyApp.AgentPatterns do
  def standard_specialist(id, actions, domain) do
    %{
      id: id,
      type: :specialist,
      actions: actions,
      signals: %{subscribes: ["review.request"], emits: ["review.result"]},
      result_builder: &standard_result_builder/2,
      metadata: %{domain: domain}
    }
  end
end

# Use pattern
MyApp.AgentPatterns.standard_specialist(
  :security,
  [CheckSQL, CheckXSS],
  :security
)
```

### 3. Documentation

```elixir
# Good - document complex configs
%{
  id: :complex_orchestrator,
  type: :orchestrator,

  # IMPORTANT: This orchestrator handles critical review path
  # It spawns security AND performance specialists for any change
  # labeled "critical" or affecting core files
  orchestration: %{
    classify_fn: fn review_data ->
      # Classification logic here...
    end,

    # These specialists run in parallel - expect 100-200ms total
    spawn_specialists: [:security_specialist, :performance_specialist],

    # Aggregation waits for BOTH specialists before emitting summary
    aggregation_fn: fn results, state ->
      # Aggregation logic here...
    end
  },

  metadata: %{
    owner: "platform-team@company.com",
    sla_ms: 200,
    criticality: :high,
    last_updated: "2025-10-29",
    change_log: "Added performance specialist to critical path"
  }
}
```

### 4. Validation

```elixir
# Good - validate configs in CI
# mix task to validate
defmodule Mix.Tasks.Synapse.ValidateAgentConfigs do
  use Mix.Task

  def run(_args) do
    case Synapse.Orchestrator.Config.load("config/agents.exs") do
      {:ok, configs} ->
        IO.puts("✓ All #{length(configs)} agent configs valid")
        :ok

      {:error, errors} ->
        IO.puts("✗ Invalid configs:")
        IO.inspect(errors, label: "Errors")
        System.halt(1)
    end
  end
end
```

---

## See Also

- [Configuration Reference](CONFIGURATION_REFERENCE.md) - Field documentation
- [Data Model](DATA_MODEL.md) - Data structures
- [Implementation Guide](IMPLEMENTATION_GUIDE.md) - Building the orchestrator
- [Architecture](ARCHITECTURE.md) - System design

---

**These examples show the power and flexibility of configuration-driven agents.**
