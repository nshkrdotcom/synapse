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

## Boundary Scans

Project code must stay free of Regex, unsafe dynamic atom creation, and
unsupervised process starts:

```sh
rg -n "~r|Regex|String\\.to_atom|GenServer\\.start\\(|Task\\.async|Task\\.start|spawn\\(|spawn_monitor|Agent\\.start" \
  -g '!deps/**' -g '!_build/**' .
```

Direct lower imports should remain absent from Synapse product code except for
the pure product-pack authoring contract:

```sh
rg -n "\\bCitadel\\b|Jido\\.Integration|ExecutionPlane|AITrace|claude|codex|gemini|OpenAI|ReqLLM|Jido\\." \
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
