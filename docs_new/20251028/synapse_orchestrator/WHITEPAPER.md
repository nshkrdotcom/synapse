# Synapse Orchestrator Whitepaper

**Puppet for Jido: Declarative, Self-Healing Multi-Agent Systems**  
**Author**: Synapse Engineering  
**Date**: 2025-10-29

---

## Executive Summary

Modern software teams need AI assistance that behaves less like a single chatbot and more like a
coordinated team of specialists. Today’s agent stacks still force builders to hand-author GenServers,
wire signal buses manually, and reinvent process supervision. Synapse Orchestrator eliminates this
boilerplate by translating declarative agent configurations into living Jido systems. It combines the
resilience of the BEAM with Jido’s action, signal, and sensor model to deliver:

- **88% code reduction** versus hand-written GenServers
- **Self-healing orchestration** with continuous reconciliation of desired vs. actual state
- **Progressive multi-agent intelligence** through coordinator archetypes and specialist pools
- **Operational guardrails** (permissions, telemetry, hot reload) baked into the runtime

This whitepaper explains the architecture, differentiators, and roadmap that make Synapse
Orchestrator the foundation for enterprise-grade agent operations on Elixir.

---

## 1. The Problem Space

| Pain Point | Traditional Approach | Impact |
|------------|---------------------|--------|
| Boilerplate agent lifecycle | Custom GenServers per agent | 200–300 LOC per agent, bug-prone restarts |
| Signal routing | Ad-hoc PubSub wiring | Fragile patterns, no causality tracking |
| Tool + behavior reuse | Copy/paste | Divergent logic, onboarding lag |
| Operations | Manual supervision | Human intervention for crashes, scaling, load |
| Compliance & observability | Afterthought instrumentation | Poor audit trails, hard to debug |

Organizations attempting to scale multi-agent workflows find themselves managing fleets of bespoke
processes. Every new specialization (security reviewer, performance analyst, documentation assistant)
requires another GenServer plus orchestration logic. The entropy multiplies when agents need to
coordinate, negotiate, and adapt based on live telemetry.

---

## 2. Vision

> **“Declare the agents you need, not the processes you must babysit.”**

Synapse Orchestrator provides a declarative control plane where teams author configurations rather
than processes. The runtime continuously ensures that the requested topology is running, healthy, and
authorized to operate. Agents become data, not code.

Key pillars:

1. **Declarative desired state** – YAML/Elixir maps define specialists, coordinators, and custom
   agents, including their signals, tools, and orchestration behaviors.
2. **Continuous reconciliation** – A runtime loop compares declared state to actual processes and
   converges automatically (spawn missing, retire stale, restart crashed).
3. **Jido-native execution** – Every agent resolves to a real `Jido.Agent.Server` with action
   schemas, sensors, and signal routing.
4. **Operational guardrails** – Permission prompts, telemetry, backpressure, and hot reloads are
   built-in.

---

## 3. Architecture Overview

```
┌──────────────────────────────┐
│ Declarative Config Layer     │
│ - %Synapse.Orchestrator.     │
│   AgentConfig{} structs       │
│ - NimbleOptions validation   │
└────────────┬────────────────┘
             │
             ▼
┌──────────────────────────────┐
│ Runtime Control Plane        │
│ Synapse.Orchestrator.Runtime │
│ - Reconcile loop             │
│ - Dependency graph           │
│ - Permission hooks           │
└────────────┬────────────────┘
             │
             ▼
┌──────────────────────────────┐
│ Agent Factory & Registry     │
│ - Convert configs -> options │
│ - Start Jido.Agent.Server    │
│ - Register RunningAgent      │
└────────────┬────────────────┘
             │
             ▼
┌──────────────────────────────┐
│ Jido Execution Fabric        │
│ - Actions & skills           │
│ - Signal.Bus (CloudEvents)   │
│ - Sensors & telemetry        │
└──────────────────────────────┘
```

### 3.1 AgentConfig Struct

The new `%Synapse.Orchestrator.AgentConfig{}` struct—backed by NimbleOptions—captures validated
configuration. It enforces archetype-specific requirements (actions for specialists, orchestration for
coordinators, custom handler for bespoke agents) and documents optional fields like state schemas and
metadata.

### 3.2 RunningAgent Struct

`%Synapse.Orchestrator.Runtime.RunningAgent{}` is the runtime’s single source of truth for active
processes. It records PID, monitor reference, spawn count, errors, and metadata. When the reconciler
detects drift (crash, unauthorized state change, updated config), it uses this record to decide
whether to restart, retire, or escalate. Each PID hosts the shared
`Synapse.Orchestrator.GenericAgent` module and delegates signal handling to the
`Synapse.Orchestrator.Actions.RunConfig` action, which fans into the configured action list and
applies custom result builders before publishing outbound signals.

### 3.3 Reconciliation Loop

The runtime periodically:

1. Refreshes configs (disk, database, or API)
2. Validates / normalizes into structs
3. Differs desired agents vs. running agents
4. Applies actions
   - Spawn missing specialists
   - Restart unhealthy processes
   - Stop agents removed from config
   - Enforce permission model

This loop is built on OTP supervisors, ensuring that orchestration itself is fault-tolerant.

### 3.4 Signal Integration

Agents declare the signals they subscribe to and emit. The factory programs `Jido.Signal.Bus` routes
accordingly, unlocking features like wildcard pattern matching, causal tracing, replay, and external
bridges (PubSub, HTTP). Coordinators can attach sensors for metrics and instrumentation without
extra code.

### 3.5 Skill Registry

`Synapse.Orchestrator.Skill.Registry` scans both Synapse (`.synapse/skills`) and Claude-style
(`.claude/skills`) directories, normalises metadata into `%Synapse.Orchestrator.Skill{}` structs, and
loads instruction bodies on demand. The runtime caches a registry PID and exposes
`Runtime.skill_metadata/1`, giving higher-level systems a ready-to-use summary for progressive
disclosure without paying the token cost upfront.

---

## 4. Differentiators

| Capability | Synapse Orchestrator | Typical Agent Orchestrator |
|------------|----------------------|-----------------------------|
| Runtime platform | Jido + BEAM (OTP) | Python async, ad-hoc event loops |
| Validation | NimbleOptions schema + structs | JSON blobs, best-effort checks |
| Signal fabric | CloudEvents-compliant `Jido.Signal.Bus` | Custom queue or naive pub/sub |
| Process resilience | Supervisor tree + `RunningAgent` records | Stateless API calls or cron jobs |
| Observability | Sensors, metadata, BEAM tracing | Limited or external add-ons |
| Progressive disclosure | Config-driven behavior, dynamic dependency wiring | Hard-coded DAGs |
| Tool safety | Permission hooks, allowed tools per archetype | Manual guardrails |

The BEAM’s process model, combined with Jido’s typed actions and signals, allows Synapse to treat
agent orchestration as first-class distributed systems engineering rather than prompt engineering.

---

## 5. Security & Compliance

1. **Permission gating** – Coordinators and custom agents can declare required approvals before
   emitting certain signals or invoking privileged actions.
2. **Allowed-tools lists** – Inspired by Claude Skills, Synapse enforces per-agent tool whitelists to
   mitigate prompt-injection or command misuse.
3. **Audit trail** – `RunningAgent.metadata` can store signal counts, last errors, and custom audit
   fields; sensors stream to structured logs.
4. **Runtime sandboxing** – Integration with OS-level sandbox (e.g., anthropic-experimental
   runtime) or container boundaries ensures controlled execution when agents shell out.

---

## 6. Roadmap Highlights

| Quarter | Initiative | Outcomes |
|---------|-----------|----------|
| Q4 2025 | Configuration hot-reload | Millisecond propagation of config changes without restarts |
| Q1 2026 | Skill marketplace integration | Declarative skill onboarding with metadata registry |
| Q1 2026 | Policy engine | OPA/Rego policies for runtime decisions (spawn, escalate, deny) |
| Q2 2026 | Multi-tenant control plane | Namespaced orchestrators with quota and billing hooks |
| Q2 2026 | Observability suite | Built-in dashboards (PromEx, Livebook) for agent health |

---

## 7. Integration Patterns

1. **Embedded** – Teams add the runtime as a child supervisor in existing Phoenix or Broadway
   applications. Configs live in `config/agents.exs` or fetched from a repo.
2. **Control-plane service** – Deploy orchestrator as its own OTP application managing agents across
   nodes; use `Jido.Signal` across the cluster.
3. **Hybrid** – Prototype agents locally with config files, then promote to centralized orchestrator
   service with remote config store (S3, Git, database).

---

## 8. Competitive Analysis

**Claude Skills** – Filesystem-based prompts with model-invoked loading. Great progressive disclosure
but lacks process resilience, typed schemas, and supervisor-grade lifecycle management. Synapse can
offer skills while still running as supervised processes.

**LangGraph / CrewAI** – Expressive Python DAGs but limited runtime health management. No BEAM-level
fault tolerance; concurrency often serialized by event loop. Synapse leverages millions of processes
with negligible overhead.

**Iterable DAG schedulers** – Tools like Temporal orchestrate workflows but aren’t agent-native (no
signals, no decisions). Synapse merges DAG-like control with adaptive agents.

---

## 9. Business Value

- **Velocity**: 88% reduction in agent code, 3× faster onboarding for new reviews, and immediate
  redeploys via configuration changes.
- **Reliability**: Self-healing ensures median recovery < 5 seconds. Coordinators reroute workloads
  when specialists fail.
- **Compliance**: Typed configs + runtime metadata produce deterministic audit trails.
- **Extensibility**: Marketplace-ready format for sharing specialist agents across teams.

---

## 10. Call to Action

Synapse Orchestrator transforms Jido from a powerful toolkit into a production-grade platform. By
declaring agents instead of coding servers, teams unlock a programmable control plane that scales
from a single security specialist to a global network of adaptive reviewers.

Next steps:

1. Pilot orchestrator with existing Stage 2 review agents.
2. Extend configuration to cover permission workflows and hot reload.
3. Package Synapse Orchestrator as an open-source library to accelerate adoption within the Jido
   ecosystem.

> **Build goals, not GenServers.**
