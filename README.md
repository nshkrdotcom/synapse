# NSHKR Agent

Synapse is the NSHKR Agent product shell over the generalized NSHKR stack. The
product boundary is AppKit. Synapse owns product-safe input normalization,
product pack metadata, and Phoenix/LiveView presentation; it does not own a
local agent runtime, workflow engine, memory store, provider client, connector
host, policy kernel, or proof harness.

## Repo Shape

```text
apps/synapse_core  headless product core and AppKit-facing wrappers
apps/synapse_web   Phoenix and LiveView shell
guides/            product architecture, feature status, and operations notes
```

Primary guides:

- [Guide Index](guides/index.md)
- [Architecture](guides/architecture.md)
- [Feature Status](guides/feature_status.md)
- [Operations](guides/operations.md)

## Current Product Surface

Synapse currently exposes:

- installation/bootstrap status
- run start, run detail, turn submission, cancel, and refresh controls
- a `staging_live` diagnostic lane that proposes a governed effect through
  AppKit before starting the run when explicit lower backends are supplied
- review queue, review detail, and review decisions
- redacted memory and context-pack projections
- tool/model grants and catalog eligibility
- team and arbitration projections
- governed-effect timelines, evidence refs, receipt refs, replay, runtime
  facts, and operations projections
- StackLab product acceptance, live-slice, and staged-live conformance proofs

User-facing UI behavior remains fixture-backed unless a guide or release claim
says otherwise. The diagnostic lane is `staging_live` only when an explicit
`AppKit.EffectSurface` backend and an AppKit agent-intake backend are supplied;
otherwise it falls back to the fixture-backed path. The browser test path uses a
deterministic governed-effect backend to render the same product states without
claiming live provider behavior. Disabled controls are explicit product state,
not hidden lower-stack failures.

The promoted governed-effect path is:

```text
Synapse UI
  -> Synapse.AgentRuns / Synapse.GovernedEffects
  -> AppKit.AgentIntake + AppKit.EffectSurface
  -> Mezzanine GovernedEffects
  -> Citadel authority
  -> Jido diagnostic lane
  -> Execution Plane diagnostic lane
  -> Mezzanine projection
  -> Synapse run/evidence readback
```

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

## Development

```sh
mix setup
mix precommit
```

Run the web server:

```sh
mix phx.server
```

Run StackLab product acceptance:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.acceptance --json
```

Run the deterministic AppKit-to-Mezzanine live-stack run slice:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.live_slice --json
```

Run the staged-live governed-effect diagnostic proof:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.staged_live.v1 --json
```

Toolchain:

```text
erlang 28.3
elixir 1.19.5-otp-28
```

## Boundary Rules

- Product code calls AppKit surfaces.
- Product code does not import lower Mezzanine runtime modules, Citadel
  internals, Jido Integration, Execution Plane, trace/export implementation
  modules, provider SDKs, or helper-runtime repos directly.
- Pure `Mezzanine.Pack` authoring contracts are allowed only for product pack
  declaration.
- Every feature is classified as `live`, `live-stack-deterministic`,
  `fixture-backed`, `disabled`, or `roadmap`.
- Product code does not handle raw credentials or raw provider payloads.
- Production processes must be supervised. Synapse currently starts no product
  worker processes of its own.
- No project code uses Regex or unsafe dynamic atom creation.
