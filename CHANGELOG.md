# Changelog

## [0.1.1] - 2025-11-29

### Added
- Dynamic signal registry (`Synapse.Signal.Registry`) replacing hardcoded signal topics
- Runtime signal topic registration via `Synapse.Signal.register_topic/2`
- Configuration-based signal topic definition in `config/config.exs`
- Generic signal types: `:task_request`, `:task_result`, `:task_summary`, `:worker_ready`
- Signal `roles` configuration in agent config for orchestrators
- `initial_state` support in orchestrator agent config
- Synapse.Domains.CodeReview module encapsulating code review functionality

### Changed
- `Synapse.Signal` now delegates to `Synapse.Signal.Registry`
- Signal topics are loaded from application config on startup
- `SignalRouter` works with dynamically registered topics
- `AgentConfig` validates topics against dynamic registry and supports roles
- `RunConfig` dispatches based on configurable `signals.roles`
- Orchestrator state uses generic keys (`tasks` instead of `reviews`)
- Code review actions moved to `Synapse.Domains.CodeReview.Actions.*`

### Deprecated
- Direct use of `:review_request`, `:review_result`, `:review_summary` signals
  (still supported via legacy aliases, will be moved to optional domain in future release)
- State keys `reviews`, `fast_path`, `deep_review` (use `tasks`, `routed`, `dispatched`)
- Synapse.Signal.ReviewRequest, Synapse.Signal.ReviewResult, etc., modules.
- Action modules under Synapse.Actions.Review, Synapse.Actions.Security, Synapse.Actions.Performance.

## v0.1.0 (2025-11-11)

- Initial release.
