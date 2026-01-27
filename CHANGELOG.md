# Changelog

## [Unreleased]

### Added
- `Synapse.DelegationRequest` struct for FlowStone delegation handoff
- `Synapse.DelegationResult` struct for coordination results
- `Synapse.coordinate/3` entry point for multi-agent coordination
- `Synapse.CoordinatorSpec` for coordination strategy configuration
- `Synapse.CoordinationState` for internal coordination state tracking
- `Synapse.Consensus` module with weighted_vote, unanimous, majority algorithms
- `Synapse.TimeoutManager` for timeout budget propagation
- `Synapse.Escalation` for human review escalation requests
- `Synapse.CoordinationTelemetry` for coordination lifecycle telemetry events
- Telemetry events: `[:synapse, :coordination, :started]`, `[:synapse, :agent, :invoked]`,
  `[:synapse, :agent, :completed]`, `[:synapse, :iteration, :completed]`,
  `[:synapse, :consensus, :checked]`, `[:synapse, :coordination, :completed]`,
  `[:synapse, :escalation, :triggered]`

## [0.1.1] - 2025-11-29

### Added
- **Domain-agnostic signal layer**: Dynamic signal registry replacing hardcoded topics
- `Synapse.Signal.Registry` for runtime topic management
- `Synapse.Signal.register_topic/2` for runtime signal registration
- Configuration-based signal topic definition
- Generic core signals: `:task_request`, `:task_result`, `:task_summary`, `:worker_ready`
- Signal `roles` configuration for orchestrator agents
- `initial_state` support in orchestrator agent config
- `Synapse.Domains.CodeReview` module encapsulating code review functionality
- Custom domains documentation guide
- Migration guide from v0.1.0

### Changed
- `Synapse.Signal` delegates to `Synapse.Signal.Registry`
- `SignalRouter` works with dynamically registered topics
- `AgentConfig` validates topics against dynamic registry and supports roles
- `RunConfig` uses config-driven signal dispatch
- Orchestrator state uses generic keys (`tasks` instead of `reviews`)
- Code review actions moved to `Synapse.Domains.CodeReview.Actions.*`

### Deprecated
- `Synapse.Signal.ReviewRequest` module (use dynamic registration)
- `Synapse.Signal.ReviewResult` module
- `Synapse.Signal.ReviewSummary` module
- `Synapse.Actions.Review.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Security.*` (use `Synapse.Domains.CodeReview.Actions.*`)
- `Synapse.Actions.Performance.*` (use `Synapse.Domains.CodeReview.Actions.*`)

### Migration
- Existing code review users should add `config :synapse, :domains, [Synapse.Domains.CodeReview]`
- See [Migration Guide](docs/guides/migration-0.1.1.md) for details

## v0.1.0 (2025-11-11)

- Initial release.
