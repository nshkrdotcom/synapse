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
