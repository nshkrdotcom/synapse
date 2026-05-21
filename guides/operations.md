# Operations

## Local Development

```sh
mix setup
mix phx.server
```

Run the release quality gate:

```sh
mix precommit
```

The precommit alias runs format check, compile with warnings as errors, and the
test suite.

## Focused Tests

```sh
MIX_ENV=test mix test apps/synapse_core/test
MIX_ENV=test mix test apps/synapse_web/test
```

## Product Acceptance

StackLab owns external product acceptance:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.acceptance --json
```

The proof receipt is fixture-backed. It proves the product path, no-bypass
posture, denial paths, memory/context projection, review decision, evidence,
and operations projection.

StackLab also owns the deterministic live-stack run slice:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.live_slice --json
```

That receipt proves explicit AppKit -> Mezzanine AgentLoop run start, turn
submission, await, runtime projection, lower/action receipt refs, memory proof
refs, no-bypass, and denied lower-effect non-submission. It does not prove live
provider behavior or production deployment.

StackLab owns the staged-live governed-effect diagnostic proof:

```sh
cd /home/home/p/g/n/stack_lab
MIX_ENV=test mix stack_lab.synapse.staged_live.v1 --json
```

That receipt proves the promoted diagnostic path:
`Synapse -> AppKit.EffectSurface -> Mezzanine.Core.GovernedEffects -> Citadel
authority -> Jido diagnostic lane -> Execution Plane diagnostic lane ->
Mezzanine readback -> Synapse`, and must report `staging_live`.

## Diagnostic Lane

The browser diagnostic lane is available from `/runs/new`. Leave the selector
blank for the normal fixture-backed run path. Select `echo` to exercise the
configured staged-live governed-effect path in test and local proof
configurations. Select `probe` to exercise the explicit authority-denied
product state when the configured backend denies that effect.

The local browser proof uses `Synapse.Fixtures.EffectSurfaceBackend` from test
configuration. It renders the same product refs and timeline states as the
StackLab proof, but it is not a live provider claim and does not require
GitHub, Linear, Codex, or other provider credentials.

## Boundary Scans

Project code must stay free of Regex, unsafe dynamic atom creation, and
unsupervised process starts:

```sh
rg -n -F -e 'Regex' -e '~r' apps config mix.exs \
  -g '!deps/**' -g '!_build/**'
rg -n -F -e 'String.to_atom' -e 'binary_to_atom' apps config mix.exs \
  -g '!deps/**' -g '!_build/**'
rg -n -F -e 'GenServer.start(' -e 'Task.async' -e 'Task.start' \
  -e 'spawn(' -e 'spawn_monitor' -e 'Agent.start' apps config mix.exs \
  -g '!deps/**' -g '!_build/**'
```

Direct lower imports should remain absent from Synapse product code except for
the pure product-pack authoring contract:

```sh
rg -n -F -e 'Citadel' -e 'Jido.Integration' -e 'ExecutionPlane' -e 'AITrace' \
  -e 'claude' -e 'codex' -e 'gemini' -e 'OpenAI' -e 'ReqLLM' -e 'Jido.' \
  apps config mix.exs -g '!deps/**' -g '!_build/**'
```

Expected result: no matches. `Mezzanine.Pack` is allowed only in
`Synapse.ProductPack`.

## Live Providers

This branch does not claim live provider behavior. If a future proof adds live
GitHub, Linear, or other provider calls, run those commands with secrets loaded
by prefixing the command with:

```sh
~/scripts/with_bash_secrets
```

Never echo secrets, never check in provider object IDs unless they are approved
disposable fixtures, and record cleanup status in the release evidence.
