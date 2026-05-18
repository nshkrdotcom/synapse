# Agent Instructions

This repository is the NSHKR Agent product app.

Follow the implementation packet at:

```text
/home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260518/nshkr_agent
```

## Rules

- Keep product code AppKit-only above the product boundary.
- Do not add local runtime, memory, workflow, provider, connector, policy, or
  proof kernels.
- Do not add direct Tier 4 SDK/provider/helper dependencies.
- Do not use regular expressions in project code.
- Do not create atoms from untrusted strings.
- Any process added to production code must be supervised.
- Use stable DOM IDs in LiveView tests.
- Run `mix precommit` before phase exit once dependencies are available.
