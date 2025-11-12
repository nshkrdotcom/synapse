# Synapse Roadmap – Blueprint to Post-Agent Dominance

_Last updated: 2025-11-11_

This is the authoritative roadmap for Synapse’s declarative agent platform. It supersedes earlier stage docs and exposes every major initiative—from near-term hardening to far-future speculative bets.

---

## TL;DR

- **Mission:** Deliver an adaptive, declarative multi-agent runtime that can reason, negotiate, learn, and scale across orgs without custom code per workflow.
- **Current State:** Stage 2 (declarative orchestrator + specialists) is live with telemetry and negotiation hooks.
- **Immediate Goals:** Ship Stage 3 (resilience, observability, adaptive routing) to make the runtime production-grade.
- **North Star:** A self-improving agent mesh with autonomous negotiation, marketplace dynamics, and global knowledge sharing.

---

## Snapshot (Q4 2025)

| Dimension            | Status                                                                 | Notes                                                                 |
|----------------------|------------------------------------------------------------------------|-----------------------------------------------------------------------|
| Runtime              | Declarative orchestration (coordinator + specialists)                  | `priv/orchestrator_agents.exs` drives classification/spawn/aggregate  |
| Observability        | Telemetry events wired (`[:synapse, :workflow, :orchestrator, :summary]`) | Logs emitted automatically; dashboards pending                        |
| Persistence          | Jido Workflow Engine snapshots every action                           | Request-scoped audit trail persisted in Postgres                      |
| Negotiation          | `:negotiate_fn` supported + integration tests                          | Basic conflict resolution shipped (severity tie-breaker)              |
| Documentation        | AGENTS + ROADMAP aligned to runtime-only world                         | Phoenix references removed                                            |
| Ops                   | Manual log watching only                                              | Prometheus/Loki integration planned Stage 3                           |

---

## Stage Ladder

| Stage | Name                     | Status      | Theme                               | Target Window |
|-------|--------------------------|-------------|-------------------------------------|---------------|
| 0     | Foundation               | ✅ Complete | Signal bus + registry + demo        | 2025-10       |
| 1     | Components               | ✅ Complete | Specialists, actions, state schema  | 2025-10       |
| 2     | Orchestration            | ✅ Complete | Declarative coordinator + runtime   | 2025-11       |
| LLM   | LLM Integration          | ✅ Complete | Req + providers + prompts           | 2025-10       |
| 3     | Advanced Features        | 🚧 Active   | Resilience, observability, learning | Q1 2026       |
| 4     | Marketplace & Toolchain  | 🔮 Planned  | Agent marketplace, DSL toolkit      | Q2 2026       |
| 5     | Learning Mesh            | 🔮 Planned  | Shared memory + feedback loops      | Q3–Q4 2026    |
| 6     | Planetary Scale          | 🔮 Planned  | Multi-region, self-healing mesh     | 2027+         |

---

## Stage 2 Recap (Where We Stand)

- Declarative orchestrator config powers classification → spawn → aggregation pipeline.
- Specialists defined as pure configs with `state_schema`, `actions`, `result_builder`.
- Negotiation hooks, telemetry, integration tests for Stage2 demo.
- This is the baseline for further evolution—everything else builds on this.

---

## Stage 3 – Advanced Features (In Flight)

### 3.1 Runtime Resilience

| Milestone | Description | Deliverables |
|-----------|-------------|--------------|
| Deadline tracking | `Synapse.Orchestrator.Timeouts` maintains per-review deadlines, emits partial summaries on timeout | Timeout metadata in state, telemetry dimension `status=:timeout` |
| Circuit breakers | Orchestrator monitors specialist failure rate; isolates unhealthy configs | Adaptive backoff, `:specialist_crash` telemetry enriched with breaker state |
| Replay primitives | CLI/API to replay pending workflows from persisted snapshots | `mix synapse.workflow.resume review_id` |

### 3.2 Observability Fabric

- **Metrics:** Adopt `telemetry_metrics_prometheus` for summary duration/severity counts, success/error ratios per config.
- **Logs:** Pipe orchestrator logs to Loki-compatible format with structured metadata.
- **Dashboards:** Grafana board with:
  - Summary throughput (fast-path vs deep-review)
  - Negotiation frequency + conflict resolution outcomes
  - Specialist health (timeouts, retries, breaker state)
- **Alerts:** PagerDuty/Slack hooks for:
  - >N pending reviews for >M minutes
  - Repeated negotiation stalemates
  - Missing summaries in 5× rolling SLA

### 3.3 Adaptive Routing & Learning

- Stateful classifiers (per repo/team) that bias spawn lists.
- Feedback ingestion (humans label false positives) updating specialist scar tissue automatically.
- Reinforcement hooks: scoreboard of `tool_effectiveness` influencing next run’s action list.

### 3.4 Developer Ergonomics

- DSL helpers for orchestrator configs (`use Synapse.Orchestrator.Spec`).
- Live reload of config fragments via hashed digests.
- `mix synapse.agents.plan` generating execution graph preview for any config set.

---

## Stage 4 – Marketplace & Toolchain (Q2 2026)

### 4.1 Agent Marketplace

- Reboot the legacy **MABEAM economics stack** (`lib_old/mabeam/economics.ex`, `lib_old/mabeam/coordination/market.ex`) as declarative modules:
  - Marketplace lifecycle (creation/listing/matching/transactions/analytics) ports to Stage 4’s service exchange.
  - Market GenServer concepts become runtime actions or DSL helpers for orchestrators.
- Registry of published specialist specs with metadata (domain, license, pricing).
- Governance: allowlist/denylist + sandbox enforcement.
- Payment hooks (Stripe crypto or internal credits) for third-party specialist runs.
- Ratings + telemetry-exposed performance metrics (reuse auction efficiency + competitiveness metrics from `lib_old/mabeam/coordination/auction.ex`).

### 4.2 DSL Tooling

- Visual orchestrator designer (web or CLI-based) exporting validated config.
- Schema composer for state definitions, ensuring upgrades are backward-compatible.
- Config package manager (`synapse.pkg`) for sharing specialist bundles, shipping with ported economics specs as reference templates.

### 4.3 Tool/Action Ecosystem

- Standard library of tools: Repo diff mining, SAST connectors, secret scanners, perf profilers.
- Toolchain dependency graph ensures required binaries/LLMs are available per agent.
- Sandboxed tool execution with WASM wrappers for untrusted third-party actions.

---

## Stage 5 – Learning Mesh (Q3–Q4 2026)

### 5.1 Shared Knowledge Graph

- Global vector store keyed by review characteristics (language, stack, severity).
- Specialists consult the mesh before running, biasing toward historically effective checks.
- Diffs auto-linked to prior incidents to accelerate remediation suggestions.
- `lib_old/mabeam/economics.ex` performance-based pricing hooks become part of the feedback loop (pricing adjusts via shared metrics).

### 5.2 Human Feedback Loops

- Review portal for human arbitration; results feed agent success/failure metrics.
- Weighted learning: specialists prioritize feedback from trusted reviewers.
- Automatic pattern extraction updating `state_schema` fields (scar tissue, success patterns).

### 5.3 Collaborative Negotiation

- Multi-agent debate protocols:
  - Structured arguments with claims/evidence/refs.
  - Consensus scoring (majority, weighted expertise).
  - Escalation policy driven by disagreement types (security vs perf vs style).

### 5.4 Continuous Benchmarking

- Synthetic workloads (diff corpora) replayed nightly, scoring each specialist.
- Leaderboard driving marketplace placement and auto-scaling priorities.

---

## Stage 6 – Planetary Scale (2027+)

### 6.1 Multi-Region Runtime Mesh

- Region-aware orchestrator clusters with shared metadata plane (ETCD/CRDT).
- Automatic failover + blue/green deployments for configs/infrastructure.
- Secure multi-tenancy with workload isolation and per-tenant quotas.

### 6.2 Self-Healing Agents

- Agents detect drift in performance and request retraining or replacement automatically.
- Dependency graph ensures new actions pass simulation harness before promotion.

### 6.3 Compliance + Audit

- Immutable audit ledger (append-only store) for all summaries/negotiations.
- Policy engine enforcing compliance (e.g., certain orgs require human-in-loop).
- Data residency enforcement: per-tenant knowledge shards stored in-region.

---

## Bleeding-Edge Initiatives (Beyond Table Stakes)

### A. Intent-Weaving Coordinator

- Multi-intent orchestration: coordinator ingests product specs / business goals and aligns reviews accordingly.
- Weighted objective function balancing security, performance, velocity.
- Adaptive classification using reinforcement from deployment metrics (post-merge incidents, rollbacks).

### B. Sensemaker Memory Plane

- Temporal event stream combining diffs, summaries, negotiations, human feedback.
- Agents can query “how did we resolve similar conflicts last quarter?” before deciding.
- Emerging behavior detection (e.g., trending issue types) triggers automatic playbook generation.
- Incorporate historical auction/market stats (from `lib_old/mabeam/coordination/market.ex` analytics) so runtime can correlate economic signals with coordination outcomes.

### C. Autonomous Sandbox Architects

- Specialized agents that create ephemeral sandboxes, run targeted tests/benchmarks based on review context, feed results back into negotiation.
- On-the-fly environment synthesis (Docker/Nix) derived from repo manifests.

### D. Cross-Org Federation

- Secure federation protocol for sharing anonymized patterns between companies.
- Reputation system for agent publishers across tenants.
- Collective defense mode: when one tenant sees a new class of vulnerability, the pattern propagates to others within minutes.

### E. Behavioral Economics Layer

- Internal currency for agent actions; specialists “bid” to participate based on confidence.
- Incentive mechanisms to reduce redundant work and encourage discovery of high-impact issues.
- Marketplace analytics predicting demand for new specialists/tools.

### F. Simulation Orchestra

- Large-scale sim harness generating synthetic diffs (SQLi, XSS, perf regressions) to continuously probe specialist coverage.
- Mutation testing for agents: intentionally inject faults into findings to ensure negotiation/escalation works.

---

## Speculative Horizon (Visionary Bets)

### 1. Self-Composing Agents

- DSL compiler that evolves orchestrator configs by analyzing telemetry (e.g., auto-add new specialist when severity spikes in a domain).
- Genetic algorithms exploring alternative orchestration strategies, auto-promoting winners.

### 2. Cognitive Twin Mesh

- Each major codebase gets a “cognitive twin” agent that tracks architecture shifts, anti-pattern creep, product goals.
- Twins collaborate with orchestrator to enforce architectural intent, not just code correctness.

### 3. Reality-Linked Negotiation

- Orchestrator subscribes to production telemetry (latency, error spikes) and reopens reviews when regressions correlate with merged diffs.
- Agents use real-world data as evidence during negotiation, closing the loop between review and runtime behavior.

### 4. Synthetic Hiring & Training

- Agent marketplace evolves into a training ground: specialists earn ranks, unlock advanced toolchains, mentor sub-agents.
- Human teams “hire” agent squads with SLAs, budgets, and OKRs encoded in orchestrator policies.

### 5. Distributed Cognition Mesh

- Thousands of lightweight agents embedded in editors, CI pipelines, runtime hooks—all reporting into Synapse.
- Mesh uses gossip protocols to converge on global insights (e.g., “Rust perf regressions rising across org”).

### 6. Regulative AI Board

- Autonomous governance agent that audits other agents for bias, drift, compliance.
- Board can veto orchestrator decisions, require human arbitration, or sandbox suspicious specialists.

### 7. Hypermodular Tool Foundry

- Agents synthesize new tools on the fly (code transforms, analyzers) when existing ones lack coverage.
- Tool candidates run through simulation orchestra before being accepted into the marketplace.

---

## Execution Cadence & Ownership

| Quarter | Focus                              | Lead | KPIs |
|---------|-------------------------------------|------|------|
| Q1 2026 | Stage 3: resilience + observability | Runtime Team | SLA: summaries <2m, timeout rate <1% |
| Q2 2026 | Marketplace + DSL toolkit           | Platform Team | 10 external specialists onboarded |
| Q3 2026 | Learning mesh + feedback loops      | Intelligence Team | False positive rate ↓30% |
| Q4 2026 | Federation + benchmarking           | Ops + Platform | Cross-tenant pattern propagation <15m |
| 2027+   | Planetary scale + speculative bets  | Entire org | Multi-region, self-healing, autonomous governance |

---

## Call to Action

1. **Stage 3 build-out** (resilience/metrics/learning) is the immediate priority—every team should align backlog items accordingly.
2. **Marketplace/DSL spike** work should begin in parallel (platform team) to avoid blocking Stage 4.
3. **Speculative R&D**: seed small squads to explore Intent-Weaving, Sensemaker, and Simulation Orchestra so prototypes exist before we formally schedule them.

This document should grow with each deliverable. Update the relevant section whenever an initiative starts, lands, or pivots. When in doubt, describe the future in embarrassing detail, then build toward it.
