# synapse_web

`synapse_web` is the Phoenix and LiveView shell for NSHKR Agent. It renders
product-safe projections from `synapse_core`; it must not duplicate AppKit
wrapper logic or call lower platform packages directly.

## Routes

```text
/
/runs
/runs/new
/runs/:id
/reviews
/reviews/:id
/memory
/memory/:id
/context-packs/:id
/tools
/catalog
/catalog/:id
/teams
/teams/:id
/arbitration/:id
/evidence
/evidence/:id
/operations
```

## Testing

LiveView tests assert stable IDs and product states rather than brittle HTML
fragments.

```sh
MIX_ENV=test mix test apps/synapse_web/test
```

The UI shows disabled and fixture-backed posture explicitly. It must not imply
live provider behavior unless a lower AppKit-backed proof exists.
