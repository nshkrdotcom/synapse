# Remediation Plan – ADR-0002

## Objective

Split Synapse into a reusable Runtime Kernel (bus + registry + specialists + shared config) and adapter layers (Phoenix, CLI, tests) so multiple independent runtimes can coexist without global state.

## Tasks

1. **Introduce `Synapse.Runtime`**
   - [ ] Create `Synapse.Runtime` with a child_spec that starts: `Jido.Signal.Bus`, `Synapse.AgentRegistry`, (future) specialist supervisor, and telemetry hooks based on options.
   - [ ] Ensure `start_link/1` returns a struct containing handles (`bus`, `registry`, runtime `pid`).

2. **Refactor Coordinator & Specialists**
   - [ ] Replace hard-coded atoms in all modules with runtime handles supplied via options (`%Runtime{bus: ..., registry: ...}`).
   - [ ] Update `Synapse.Agents.CoordinatorAgentServer.start_link/1` to accept either a runtime struct or discrete bus/registry references; prefer the struct to avoid option proliferation.
   - [ ] Propagate handles through workflows/integration tests so everything references the runtime they spun up.

3. **Rework Phoenix Application**
   - [ ] Strip bus/registry startup from `Synapse.Application` and instead supervise `{Synapse.Runtime, otp_app: :synapse, name: Synapse.Runtime}` plus `SynapseWeb.Endpoint`.
   - [ ] Provide `Synapse.Runtime.from_config/1` helper so Phoenix can load runtime options from `config/*.exs`.

4. **Testing Support**
   - [ ] Replace ad-hoc `setup_test_bus/2` helper with `Synapse.RuntimeCase`, which starts a runtime per test and exposes its handles.
   - [ ] Migrate existing tests (coordinator, integration, workflows) to the new helper.

5. **Tooling & Docs**
   - [ ] Update README / docs to explain how to start a runtime programmatically (`{:ok, runtime} = Synapse.Runtime.start_link(...)`).
   - [ ] Document lifecycle and shutdown semantics so adapters know how to stop runtimes in supervision trees.

## Verification

* `mix test` passes without starting global `:synapse_bus` / `:synapse_registry`.
* Running `iex -S mix` shows Phoenix booting a runtime child explicitly; other adapters (integration tests, demos) use the runtime helper instead of `start_supervised!({Synapse.AgentRegistry, ...})`.
* Integration tests confirm multiple runtimes (or multiple coordinator instances) can run simultaneously without conflicting specialist IDs or signals.

## Risks

* **Refactor blast radius:** Many modules currently fetch bus/registry implicitly. Mitigate by introducing a runtime struct quickly and refactoring modules in layers (agents → workflows → adapters).
* **Adapter migration:** Phoenix is the only shipping adapter today, but future adapters must adopt the kernel too; document the upgrade path clearly.
