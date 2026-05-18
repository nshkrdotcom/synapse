# NSHKR Agent

Synapse is being rebuilt as NSHKR Agent: a Phoenix product shell over the
generalized NSHKR stack.

The product boundary is AppKit. Synapse does not implement a local agent
runtime, workflow engine, memory store, provider client, connector host, policy
kernel, or proof harness.

## Current Shape

```text
apps/synapse_core  headless product core
apps/synapse_web   Phoenix and LiveView shell
```

Phase 2 adds the neutral product pack and bootstrap layer:

- `Synapse.Config`
- `Synapse.PlatformContext`
- `Synapse.ProductProfile`
- `Synapse.ProductPack`
- `Synapse.ProductInstallTemplate`
- `Synapse.DefaultAuthoringBundle`
- `Synapse.ProductBootstrap`

Phase 3 adds fixture-backed run and turn workflows over AppKit DTOs:

- `/runs`
- `/runs/new`
- `/runs/:id`
- `Synapse.AgentRuns`
- `Synapse.Turns`
- `Synapse.Reviews`

Installation, run start, turn submission, cancel, and refresh remain
fixture-backed unless AppKit live backends are explicitly supplied and proven in
the calling environment. Review queue/detail/decision are fixture-backed in the
same way.

Phase 5 adds fixture-backed redacted memory and context-pack projections:

- `/memory`
- `/memory/:id`
- `/context-packs/:id`
- `Synapse.Memory`
- `Synapse.ContextPacks`

Memory projection construction uses `AppKit.MemorySurface`; feedback writes are
disabled until a product AppKit memory-write backend exists. Later phases wire
catalog, teams, evidence, operations, and StackLab acceptance proof.

Phase 6 adds read-only tool, model, budget, cost, and catalog eligibility
projections:

- `/tools`
- `/catalog`
- `/catalog/:id`
- `Synapse.Catalog`

Catalog assignment and marketplace economics stay disabled until a governed
platform assignment backend is proven.

Phase 7 adds fixture-backed team and arbitration projections:

- `/teams`
- `/teams/:id`
- `/arbitration/:id`
- `Synapse.Teams`
- `Synapse.Arbitration`

Team control and arbitration memory writes stay disabled because the available
coordination/hive surfaces are DTO/projection oriented. Final arbitration
decisions route through the AppKit review surface.

## Development

```sh
mix setup
mix precommit
```

This repo uses the same Elixir/Erlang toolchain as the active AppKit and
Mezzanine packages:

```text
erlang 28.3
elixir 1.19.5-otp-28
```

Run the web server:

```sh
mix phx.server
```

## Boundary Rules

- Product code calls AppKit surfaces.
- Product code does not import lower Mezzanine, Citadel, Jido Integration,
  Execution Plane, AITrace, provider SDK, or helper-runtime modules directly.
- Every feature is classified as `live`, `fixture-backed`, `disabled`, or
  `roadmap`.
- No product code handles raw credentials or raw provider payloads.
- Processes started by product code must be children of a supervision tree.
