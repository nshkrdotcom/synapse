# Architecture

Synapse is a product shell. Its upper boundary is AppKit, and all lower runtime,
authority, connector, memory, workflow, trace, and proof behavior stays behind
that boundary.

## Layers

```text
Synapse LiveView UI
  -> synapse_core product modules
  -> AppKit surfaces and DTOs
  -> lower stack owners behind AppKit
```

Synapse may declare product pack data through the pure `Mezzanine.Pack`
authoring contract. It must not import Mezzanine runtime/workflow modules or
other lower owners directly.

## Product Core

`synapse_core` owns:

- product configuration and bootstrap posture
- AppKit request-context construction
- product pack and install-template data
- fixture-backed product wrappers
- product-safe projections and denial states

It does not own:

- local agent runtime
- workflow engine
- memory store
- provider or connector client
- policy or authority engine
- proof harness

## Web Shell

`synapse_web` owns rendering and form handling. It calls `synapse_core`, not
lower platform packages. LiveViews render stable, testable product states:
accepted, pending, denied, disabled, fixture-backed, and missing evidence.

## AppKit Surfaces Used

- `AppKit.AgentIntake`
- `AppKit.HeadlessSurface`
- `AppKit.InstallationSurface`
- `AppKit.MemorySurface`
- `AppKit.ModelSurface`
- `AppKit.SkillSurface`
- `AppKit.BudgetSurface`
- `AppKit.ContextBudgetSurface`
- `AppKit.CostSurface`
- `AppKit.CoordinationSurface`
- `AppKit.HiveSurface`
- `AppKit.ReplaySurface`
- `AppKit.Core` DTOs

## Proof Boundary

StackLab owns the external product acceptance proof. The proof calls Synapse
product APIs from outside the Synapse repo and records a no-bypass receipt over
Synapse product code.
