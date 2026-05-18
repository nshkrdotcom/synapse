# Changelog

## Unreleased

- Reset Synapse onto the `nshkr-agent-rewrite-20260518` branch.
- Replace the old local-runtime application shape with an umbrella scaffold:
  `apps/synapse_core` and `apps/synapse_web`.
- Add AppKit-facing product pack, bootstrap, run, turn, review, memory,
  context, catalog, team, arbitration, evidence, and operations modules.
- Add Phoenix/LiveView routes for the full fixture-backed product surface.
- Add documentation guides for architecture, feature status, and operations.
- Add StackLab product acceptance proof through
  `mix stack_lab.synapse.acceptance --json`.
