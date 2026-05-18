# synapse_core

Headless product core for NSHKR Agent.

This app owns product-safe input normalization, feature classification, AppKit
request-context construction, neutral pack data, and fixture-backed bootstrap
state. It must not own lower runtime, workflow, memory, provider, connector,
policy, or proof behavior.

Phase 2 public modules:

- `Synapse.Config`
- `Synapse.PlatformContext`
- `Synapse.ProductProfile`
- `Synapse.ProductPack`
- `Synapse.ProductInstallTemplate`
- `Synapse.DefaultAuthoringBundle`
- `Synapse.ProductBootstrap`

Phase 3 run modules:

- `Synapse.AgentRuns`
- `Synapse.Turns`
- `Synapse.Fixtures.AgentIntakeBackend`
- `Synapse.Fixtures.HeadlessBackend`

Phase 4 review modules:

- `Synapse.Reviews`
- `Synapse.Fixtures.ReviewSurface`

Phase 5 memory/context modules:

- `Synapse.Memory`
- `Synapse.ContextPacks`

Memory projections are redacted AppKit DTOs. Context packs remain fixture-backed
until a final product context-pack surface exists. Feedback writes are disabled.

Phase 6 catalog module:

- `Synapse.Catalog`

Catalog projections use AppKit model, skill, budget, context-budget, and cost
DTO surfaces. Assignment and marketplace economics are disabled.

Phase 7 team/arbitration modules:

- `Synapse.Teams`
- `Synapse.Arbitration`

Coordination and hive projections are fixture-backed DTO views. Mutating team
control and memory-write paths remain disabled.
