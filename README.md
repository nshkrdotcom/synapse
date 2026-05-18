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

Phase 1 exposes a fixture-backed dashboard shell. Later phases wire AppKit
product pack bootstrap, run intake, turn submission, review, memory/context,
catalog, evidence, and StackLab acceptance proof.

## Development

```sh
mix setup
mix precommit
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
