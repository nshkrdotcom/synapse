# synapse_core

`synapse_core` is the headless product core for NSHKR Agent. It owns product
configuration, AppKit request context construction, product pack data, and
product view models.

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

## Runtime Composition

Run acceptance and durable snapshot/cursor readback require an injected
`AppKit.BackendStack`. Production configuration supplies a provider module with
`backend_stack/0`; missing intake or headless roles fail closed.

Deterministic AppKit doubles live under test support and are explicitly selected
by tests. They are not compiled into the normal product release.

## Feature Posture

- Run and turn commands route through the injected AppKit backend stack.
- Run lists, durable detail, and event cursors are read from AppKit projections.
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
