# Continuation Prompt

Use this prompt when resuming work on Synapse’s declarative agent runtime. It captures the current state, critical references, and the most valuable next moves.

---

## Context Snapshot

- **Synapse Runtime:** Declarative orchestrator + specialists live in `priv/orchestrator_agents.exs`, executed via `Synapse.Orchestrator.Runtime`.
- **Telemetry:** `Synapse.Telemetry` attaches `[:synapse, :workflow, :orchestrator, :summary]` handlers by default; logs include config_id, severity, negotiation counts.
- **Documentation:** `AGENTS.md` and `ROADMAP.md` describe the runtime-only architecture; `ROADMAP.md` now references legacy economics modules for future marketplace work.
- **Legacy Market Stack:** The entire agent-market-dynamics implementation lives under `lib_old` (see “Required Reading” below). Nothing comparable exists in `lib/` yet.

---

## Required Reading / Reference

1. **ROADMAP.md** – outlines stages 3–6, marketplace plans, bleeding-edge ideas. Highlights legacy files to port.
2. **lib_old/mabeam/economics.ex** – full economics service (marketplace APIs, dynamic pricing, prediction markets, performance-based pricing).
3. **lib_old/mabeam/coordination/market.ex** – market-coordination GenServer (order books, equilibrium finding, statistics).
4. **lib_old/mabeam/coordination/auction.ex** – auction outcomes, efficiency/value-density metrics feeding market health.
5. **lib_old/foundation/coordination/primitives.ex** – distributed coordination primitives underlying auctions/markets.
6. **lib_old/mabeam/types.ex** – definitions for `:market_based` coordination and `market_mechanism` enums used by economics modules.

Skim these before modifying runtime or roadmap to ensure new work aligns with proven patterns.

---

## Logical Next Moves

### Option 1 – Port Economics/Marketplace Core (Stage 4 Kickoff)
- Extract marketplace lifecycle (create/list/match/execute/analytics) from `lib_old/mabeam/economics.ex`.
- Reimplement as runtime-compatible modules (no GenServers where possible); expose orchestrator actions or DSL helpers.
- Add tests replicating legacy behavior with modern data structures.
- Update ROADMAP/AGENTS with new APIs and migration guidance.

### Option 2 – Observability Build-Out (Stage 3 Goal)
- Wire telemetry into Prometheus/Loki (e.g., via `telemetry_metrics_prometheus`).
- Produce Grafana dashboards for summary throughput, negotiation frequency, specialist health.
- Add alerts for SLA breaches (missing summaries, timeouts).
- Document setup in README/ops playbook.

### Option 3 – Marketplace DSL & Config UX
- Design a declarative schema for marketplaces within `priv/orchestrator_agents.exs` (similar to specialists/orchestrator blocks).
- Provide generator macros or helper modules (e.g., `use Synapse.Orchestrator.Marketplace`).
- Build CLI tooling (`mix synapse.marketplan`) to preview config graphs and validate references.

### Option 4 – Performance-Based Pricing Prototype
- Use current telemetry to adjust agent priority or costs (e.g., weight spawn order based on severity/confidence stats).
- Persist performance metrics per agent, feeding back into classification or result negotiation.
- Validate the loop with tests/integration scenarios.

### Option 5 – Documentation + Onboarding Package
- Consolidate AGENTS.md, ROADMAP.md, and legacy references into a single “Synapse Handbook”.
- Provide “start with logs” guidance (mix commands, telemetry watchers) plus market/economics overview for new contributors.

Pick one (or a combination) based on immediate priorities. Each option builds on the existing roadmap and legacy knowledge to push the platform toward the marketplace + learning mesh milestones.
