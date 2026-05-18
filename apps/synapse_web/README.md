# synapse_web

Phoenix and LiveView shell for NSHKR Agent.

This app renders product-safe projections from `synapse_core`. It must not
duplicate AppKit wrapper logic or call lower platform packages directly.

The dashboard currently renders fixture-backed installation and operations
state from `Synapse.ProductBootstrap.fixture_status/1`.

Phase 3 routes:

- `/runs`
- `/runs/new`
- `/runs/:id`
- `/reviews`
- `/reviews/:id`
- `/memory`
- `/memory/:id`
- `/context-packs/:id`
- `/tools`
- `/catalog`
- `/catalog/:id`
- `/teams`
- `/teams/:id`
- `/arbitration/:id`
- `/evidence`
- `/evidence/:id`
- `/operations`
