# ADR-0008: Agent State Persistence & Knowledge Store

- **Status:** Proposed
- **Date:** 2025-11-09
- **Owner:** Synapse Agent Team

## Context

Specialist agents (`SecurityAgentServer`, `PerformanceAgentServer`, etc.) maintain state in in-memory structs (`Synapse.Agents.SecurityAgent`, ...). State includes scar tissue, review history, learned patterns. Once the BEAM node restarts, all accumulated knowledge disappears. There is no snapshotting, no shared knowledge store, and no way to query historical agent state outside the running process.

Problems:

1. **Volatile learning.** Scar tissue and learned patterns reset on restart, negating the whole “agents learn over time” narrative.
2. **No cross-agent sharing.** There’s no mechanism for Coordinator to inspect specialist state or for multiple instances to share knowledge.
3. **Operational blind spots.** We cannot audit how an agent’s internal state influenced a decision because state isn’t persisted or exposed.

## Decision

Introduce an Agent State & Knowledge Store with the following features:

* **Snapshotting:** Specialists periodically persist their state (or deltas) to the store. On startup, they load the latest snapshot.
* **Queryable history:** Provide APIs to fetch agent metrics (e.g., scar tissue entries) for debugging or analytics.
* **Pluggable backend:** Default implementation can use ETS + disk-backed snapshots; allow adapters for databases (Postgres, DynamoDB).
* **Coordinator awareness:** Coordinator can request read-only views of specialist state to inform decisions (e.g., “security agent overloaded, schedule differently”).

## Consequences

* Agent servers must serialize their state (via `Jason` or term-to-binary) and schedule snapshot jobs.
* Tests must stub the store to avoid I/O.
* Versioning is necessary: store schema evolution should handle state changes between releases.

## Alternatives Considered

1. **Rely on BEAM state only.**  
   Rejected: unacceptable for production resilience and learning narratives.

2. **Use existing ETS tables with manual persistence.**  
   Rejected: ad hoc persistence is error-prone; a dedicated store interface keeps responsibilities clear.

## Related ADRs

* ADR-0002 runtime kernel will start the store per runtime or inject handles.
* ADR-0006 observability can leverage the store for exposing agent statistics.
