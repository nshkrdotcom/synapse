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
- staged-live diagnostic governed-effect coordination
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
- `AppKit.EffectSurface`
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

## Governed-Effect Path

The promoted diagnostic path is the only `staging_live` Synapse path in this
branch:

```text
Synapse RunNewLive / RunShowLive / EvidenceShowLive
  -> Synapse.AgentRuns and Synapse.GovernedEffects
  -> AppKit.AgentIntake and AppKit.EffectSurface
  -> Mezzanine.Core.GovernedEffects
  -> Citadel.AuthorityContract.GovernedEffectAuthority
  -> Jido.Integration.Lanes.DiagnosticLane
  -> ExecutionPlane.Lanes.DiagnosticLane
  -> Mezzanine projection/readback
  -> Synapse governed-effect and evidence projections
```

`Synapse.GovernedEffects` sends the immutable tool manifest and exact reviewed
file-operation digest through `AppKit.EffectSurface`. Review approval is
recorded through `AppKit.ReviewSurface`; dispatch, lower acceptance, receipt,
ambiguity, and continuation then return as one durable
`AppKit.Core.GovernedEffectDTO`. Synapse never imports the lower review,
authority, runtime, provider, credential, or workspace owners.

Product readback renders only that AppKit projection. Tests explicitly inject
AppKit-shaped backends from `test/support`; no fixture backend is compiled into
the production product and no deterministic test result is advertised as live
provider behavior.

## Proof Boundary

StackLab owns the external product acceptance proof. The proof calls Synapse
product APIs from outside the Synapse repo and records a no-bypass receipt over
Synapse product code.

StackLab also owns the deterministic live-stack run-slice proof. That proof
injects the AppKit Mezzanine bridge and Mezzanine AgentLoop runtime adapter from
outside Synapse, then proves run start, turn submission, await, runtime
projection, lower/action receipt refs, memory proof refs, and denied
lower-effect non-submission. Synapse product code still imports only AppKit
surfaces plus the pure `Mezzanine.Pack` authoring contract.

StackLab also owns the staged-live governed-effect proof. That proof injects
the AppKit Mezzanine bridge, runs the deterministic diagnostic lane through the
new governed-effect path, verifies authority/dispatch/receipt/evidence refs and
timeline status, and confirms the receipt reports `staging_live`.
