# synapse_core

`synapse_core` is the headless product core for NSHKR Agent. It owns product
configuration, AppKit request context construction, product pack data, product
view models, and fixture-backed product flows.

It must not own lower runtime, workflow, memory store, provider, connector,
policy, or proof behavior.

## Public Modules

- `Synapse.Config`
- `Synapse.PlatformContext`
- `Synapse.ProductProfile`
- `Synapse.ProductPack`
- `Synapse.ProductInstallTemplate`
- `Synapse.DefaultAuthoringBundle`
- `Synapse.ProductBootstrap`
- `Synapse.AgentRuns`
- `Synapse.Turns`
- `Synapse.Reviews`
- `Synapse.Memory`
- `Synapse.ContextPacks`
- `Synapse.Catalog`
- `Synapse.Teams`
- `Synapse.Arbitration`
- `Synapse.Evidence`

## Fixture Backends

- `Synapse.Fixtures.AgentIntakeBackend`
- `Synapse.Fixtures.HeadlessBackend`
- `Synapse.Fixtures.ReviewSurface`

These are deterministic product fixtures for tests and acceptance. They are not
provider adapters or lower runtime implementations.

## Feature Posture

- Run and turn commands route through AppKit DTOs and fixture backends.
- Reviews route through an injectable AppKit-shaped review surface.
- Memory uses `AppKit.MemorySurface` projections and rejects raw payloads.
- Context packs are fixture-backed until a stable AppKit product surface is
  finalized.
- Catalog displays AppKit model, skill, budget, context-budget, and cost
  projections.
- Team/arbitration views are fixture-backed DTO projections; executable team
  control remains disabled.
- Evidence and operations are fixture-backed AppKit projections. Trace export is
  not used as operational metrics truth.
