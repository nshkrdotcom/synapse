# Synapse Orchestrator Skill Architecture

**Objective**: Provide an agent-native skill system that integrates tightly with Synapse Orchestrator
while surpassing filesystem-only approaches (e.g., Claude Code Skills) in adaptability, safety, and
observability.

---

## 1. Design Principles

1. **Agent-first** – Skills are executable behaviors owned by agents, not static prompt bundles. They
   can maintain state, subscribe to signals, and emit results.
2. **Progressive disclosure** – Inspired by Claude Skills, metadata is always available while heavy
   content loads only when required.
3. **Typed + auditable** – Skill definitions are validated via `%AgentConfig{}` extensions and stored
   as versioned resources with change history.
4. **Composable** – Coordinators can assemble skill pipelines dynamically based on context, telemetry,
   or negotiation with other agents.
5. **Safe by default** – Tool usage and command execution flow through Orchestrator permissions and
   the Jido Signal Bus, preserving isolation.

---

## 2. Conceptual Model

```
SkillRegistry
  │
  ├─ SkillMetadata
  │    ├─ name
  │    ├─ description (semantic matching)
  │    ├─ allowed_tools
  │    ├─ version / checksum
  │    └─ archetype (:read_only | :transform | :interactive)
  │
  └─ SkillArtifact (optional lazy payload)
       ├─ instructions (markdown / heex)
       ├─ action modules (Jido.Action)
       ├─ scripts (executed in sandbox)
       └─ reference docs
```

### Storage

- **Primary**: `%Synapse.Orchestrator.Skill{}` struct persisted in ETS/DB with references to blob
  storage (S3, Git) for large artifacts.
- **Filesystem fallback**: `.synapse/skills/` directory for local development, compatible with
  `.claude/skills/` to ease migration.

### Lifecycle

1. Config declares required skills by id or capability tag.
2. Runtime ensures skills are fetched, validated, and cached.
3. Agents request skills via `Jido.Signal` message (`skill.request`).
4. Registry replies with metadata; orchestrator mediates permission prompts.
5. On approval, the skill artifact is streamed to the requesting agent or mounted as an OTP child if
   it’s executable.

---

## 3. Comparison with Claude Code Skills

| Area | Claude Code | Synapse Skill System |
|------|-------------|----------------------|
| Representation | Markdown + YAML files | Typed structs + optional artifacts |
| Invocation | Model reads files via bash | Agents send signals; runtime brokers access |
| Statefulness | Stateless instructions | Skills can mount actions, sensors, state schemas |
| Permissions | CLI prompt per skill | Fine-grained policies integrated with Orchestrator perms |
| Observability | CLI logs only | RunningAgent.metadata + sensors + PromEx metrics |
| Distribution | Local filesystem | Pluggable backends (filesystem, Git, S3, registry) |
| Composition | Implicit multiple skills | Coordinators can pipeline skills, negotiate usage |

This architecture treats skills as first-class agent behaviors rather than passive prompt bundles.

---

## 4. Data Structures

```elixir
defmodule Synapse.Orchestrator.Skill do
  @typedoc """Declarative skill definition."""
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          version: String.t(),
          allowed_tools: [atom()],
          artefact_ref: {:fs, Path.t()} | {:repo, String.t()} | {:blob, binary()},
          checksum: String.t(),
          metadata: map()
        }

  defstruct [
    :id,
    :name,
    :description,
    :version,
    :artefact_ref,
    :checksum,
    allowed_tools: [],
    metadata: %{}
  ]
end
```

`%Synapse.Orchestrator.AgentConfig{}` gains a `skills` field:

```elixir
skills: [
  %{skill_id: "pdf-parser", mode: :inline},
  %{skill_id: "compliance-check", mode: :detached, timeout_ms: 5_000}
]
```

Modes:

- **:inline** – Load instructions and actions into the agent’s process (progressive disclosure).
- **:detached** – Spawn a dedicated specialist agent from the skill artefact.
- **:tooling** – Expose skill as a scoped tool with allowed commands.

---

## 5. Runtime Flow

1. **Skill Discovery** – `Skill.Registry.refresh/1` reads configured directories and repositories,
   returning `%Skill{}` records.
2. **Metadata Injection** – Runtime adds skill summaries to agent context (similar to system prompt
   injection) but via OTP message (`{:skills, catalog}`) to keep token cost low.
3. **Activation** – When an agent needs a skill, it emits `skill.request` signal. Orchestrator checks
   permissions (policy + user preferences) and, if approved, streams artefact content or attaches
   the skill module.
4. **Execution** – Skills run as `Jido.Action` modules, sensors, or subordinate agents, benefiting
   from supervision and telemetry.
5. **Audit** – Completed skill runs emit `skill.completed` signals with summary, errors, and metrics.

---

## 6. Progressive Disclosure Mechanics

| Level | Data | Transport | Token Cost |
|-------|------|-----------|------------|
| 0 | Skill metadata (name, description, allowed tools) | Injected via context assign | ~40 tokens | 
| 1 | Instruction body | Streamed on demand, cached in ETS | 300–2,000 tokens |
| 2 | Artefact dependencies (scripts, docs) | File streaming, executed in sandbox | Only outputs |
| 3 | Derived agents/actions | Spawned processes (no tokens) | 0 tokens |

Agents retain metadata and release artefacts when no longer needed, minimizing memory usage.

---

## 7. Security Model

- **Policy engine**: Optional Rego/OPA integration to enforce “skill X requires approval from role Y”.
- **Allowed tools**: Skills declare permitted tools; orchestrator rejects unauthorized calls.
- **Capability tokens**: Temporary tokens passed to agents to limit skill usage window (similar to
  macaroon-style delegation).
- **Sandboxing**: Run external scripts within anthropic-experimental sandbox or Docker, capturing
  stdout/stderr only.

---

## 8. Migration From Claude Skills

1. Drop existing directories into `.synapse/skills/` (compatible metadata).
2. Add optional `skill.config.exs` to declare action modules or sensors.
3. Run `mix synapse.skills.import` to convert into `%Skill{}` structs with checksums.
4. Update agent configs to reference imported skills (`skills: [%{skill_id: "pdf-parser"}]`).

The runtime will continue to support `.claude/skills/` for teams co-running Claude Code.

---

## 9. Milestones

| Milestone | Scope | Timeline |
|-----------|-------|----------|
| M1 Prototype | Skill struct + registry, inline mode | 2 weeks |
| M2 Orchestration | Detached mode, permission prompts, audit signals | 4 weeks |
| M3 Marketplace | Remote repository support, version negotiation | 6 weeks |
| M4 Policy & Sandbox | OPA integration, sandbox execution pipeline | 8 weeks |

---

## 10. Outcomes

By embedding skills inside Synapse Orchestrator we gain:

- **Agentic composition** – Coordinators can negotiate which skills to invoke, using Jido signals as
  a lingua franca.
- **Operational excellence** – Skills inherit the same telemetry and failure handling as agents.
- **Governance** – Administrators control availability, versions, and permissions centrally.
- **Compatibility** – Existing Claude Code skills port with minimal friction while benefiting from
  OTP-grade supervision.

This blueprint delivers a skills ecosystem that stays model-agnostic but becomes process-native,
surpassing current filesystem-only implementations.
