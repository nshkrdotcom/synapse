# Synapse Multi-Agent Framework Vision

## Context

We are standing up a production-grade agent platform on top of the local Jido toolchain (`agentjido/jido`, `agentjido/jido_signal`, `agentjido/jido_action`). The goal is to graduate from a single `CriticAgent` pipeline into a resilient network of specialists orchestrated through signals, directives, and shared state. This document sketches two horizons:

1. **Stage 1 (MVP)** – the concrete feature we will build next, using TDD.
2. **Stage 2 (Full Platform)** – the north-star architecture that Stage 1 feeds into.

---

## Stage 1 – MVP Feature (What We Build Now)

### Objective

Deliver the first *real* multi-agent workflow: a `CoordinatorAgent` that dynamically routes code review work to two specialist agents (`SecurityAgent`, `PerformanceAgent`) and synthesizes their findings. The MVP replaces the current linear pipeline with decision-making, signal routing, and learning hooks.

### High-Level Flow

1. `CoordinatorAgent` receives a `review.request` signal (via `Jido.Signal.Bus`).
2. It classifies the change (fast path vs. deep review) and dispatches directives:
   - `Directive.Spawn` specialized agents if they are not already running.
   - `Directive.Enqueue` review instructions tailored to each specialist.
3. Specialists execute registered Jido actions (e.g. `CheckSQLInjection`, `CheckComplexity`) and emit structured `review.result` signals.
4. `CoordinatorAgent` listens for the results, synthesizes them, and emits a final `review.summary` signal.
5. State updates (review history, learned patterns, scar tissue) are stored on the agents for feedback loops.

### Scope

| What’s **in** | What’s **out** |
| --- | --- |
| Two specialists (`SecurityAgent`, `PerformanceAgent`) with 2–3 real checks each | Additional specialists (style, docs, accessibility) |
| Signal-based orchestration through `Jido.Signal.Bus` | Full marketplace or marketplace UI |
| Persistent review history + learned patterns on each specialist | Cross-session memory syncing or external DB |
| Synthesis action (`GenerateSummary`) that merges specialist results | Human escalation, negotiation, or marketplace matching |
| Feature toggles for fast-path vs. deep-review | Long-term learning/feedback loops beyond in-memory state |

### Test-Driven Backbone

We build the MVP with TDD, using a tight matrix of tests:

1. **Action tests** (ExUnit) for each new Jido action (e.g. `CheckSQLInjection`) to verify schemas, error handling, and output.
2. **Agent tests** for each specialist:
   - State updates (`learned_patterns`, `scar_tissue`) using the existing helper DSLs.
   - Signal handling (`review.request`, `review.result`) to ensure proper directive and signal flows.
3. **Coordinator integration test** using `Jido.Signal.Bus` + LiveView-style `LazyHTML` helpers to verify:
   - Proper spawn/enqueue directives.
   - Correct signal routing and summary synthesis.
4. **End-to-end test** that publishes a `review.request` signal and asserts the final `review.summary` output.

Every failing test becomes a task in the Stage 1 backlog. We keep the `mix precommit` pipeline green at each step.

### Deliverables

| Path | Description |
| --- | --- |
| `lib/synapse/agents/coordinator_agent.ex` | New agent orchestrating specialists via directives and signals. |
| `lib/synapse/agents/security_agent.ex` | Specialist agent registering security actions + state tracking. |
| `lib/synapse/agents/performance_agent.ex` | Specialist agent registering performance actions + state tracking. |
| `lib/synapse/actions/security/*.ex` | Jido actions for SQL injection, XSS, auth checks, etc. |
| `lib/synapse/actions/performance/*.ex` | Jido actions for complexity, memory, benchmark checks. |
| `test/synapse/agents/**/*` | Unit tests, integration tests, and end-to-end signal tests. |
| `docs/20251028/...` | Updated runbook describing the MVP architecture (this doc). |

---

## Stage 2 – Full Platform (Where We Are Headed)

### Vision Snapshot

| Layer | Capabilities |
| --- | --- |
| **Coordinator Network** | Multiple `CoordinatorAgent` instances that classify work, form agent teams, and negotiate strategies (urgent vs. thorough vs. learning). |
| **Specialist Ecosystem** | Plug-and-play agents (security, performance, style, docs, accessibility, domain-specific) with `Directive.RegisterAction`-driven toolkits. |
| **Signal Fabric** | Rich `Jido.Signal` bus with CloudEvents-compliant payloads, streams, snapshots, replay, and causality tracking (`Jido.Signal.Journal`). |
| **Marketplace & Hierarchy** | Support for junior/senior/architect agents, dynamic pricing, marketplace enrollment, and reputation-driven matchmaking. |
| **Learning Mesh** | Shared pattern libraries, success/failure tracking, feedback ingestion, and inter-agent knowledge syncing (`learned_patterns`, `tool_effectiveness`). |
| **HITL & Escalation** | Negotiating agents capable of escalation via `Jido.Signal` (`review.conflict`, `review.escalate`) with human-in-the-loop workflows. |

### Architectural Pillars

1. **Signal-First Orchestration** – Everything (requests, progress, results, negotiation, escalation) runs through `Jido.Signal` and its router/journal infrastructure.
2. **Directive-Driven Agents** – Agents remain composable and testable by responding to `Directive` instructions (`Spawn`, `Enqueue`, `RegisterAction`, `Kill`).
3. **Tool Marketplace** – Actions are first-class tools. Each specialist bundles a toolkit; future phases allow runtime tool discovery, scoring, and sharing.
4. **Adaptive Learning** – Agents capture feature patterns, track tool effectiveness, and broadcast learnings to peers (resettable, auditable state).
5. **Negotiation & Escalation** – Agents handle conflicts through the `Jido.Signal` bus, coordinate responses, and escalate sticky cases with context-rich payloads.
6. **TDD at Scale** – Every feature ships with action/agent/signal tests; future CI runs orchestrated live signal tests inside `mix precommit`.

### Phase Roadmap (Post-MVP)

1. **Phase 2** – Add StyleAgent + DocumentationAgent; implement negotiation signals and human escalation.
2. **Phase 3** – Introduce agent marketplace, reputation scores, and dynamic coordinator strategies.
3. **Phase 4** – Shared learning mesh (pattern sync, cross-agent knowledge, cluster memory).
4. **Phase 5** – Large-scale orchestration: thousands of agents, distributed signal buses, cross-repo reviews.
5. **Phase 6** – Self-improving agents (tool creation, agent training, emergent strategies) + full human-agent collaboration dashboards.

---

## Summary

- **Stage 1** delivers the first concrete multi-agent workflow: a coordinator with two specialists, signal orchestration, stateful learning, and full TDD coverage.
- **Stage 2** expands this into a world-class agentic platform: marketplace, negotiation, shared learning, and planetary scale.

Everything we ship now should be built with Stage 2 in mind—small, composable, signal-friendly components that can grow into the full architecture without rewrites.
