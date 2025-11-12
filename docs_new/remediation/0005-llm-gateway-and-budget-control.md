# Remediation Plan – ADR-0005

## Objective

Replace the global `Synapse.ReqLLM` module with a runtime-scoped LLM Gateway that enforces budgets, tracks provider capabilities, and supports both synchronous and asynchronous invocation patterns.

## Tasks

1. **Gateway Process & API**
   - [ ] Implement `Synapse.LLM.Gateway` (GenServer or pool) started per runtime; accept config struct (profiles, budgets, providers).
   - [ ] Provide public API: `call(gateway, request, opts)` for synchronous calls and `enqueue(gateway, request, opts)` for async mode returning a reference + signal delivery.
   - [ ] Define request/response structs so callers don’t pass raw maps.

2. **Provider Behaviours**
   - [ ] Introduce `Synapse.LLM.Provider` behaviour modules; migrate OpenAI/Gemini adapters to implement callbacks explicitly.
   - [ ] Support capability flags (streaming, JSON mode, tool calling) so workflows can check at runtime.

3. **Budget & Circuit Breaker**
   - [ ] Track per-profile token quotas and call counts; expose configuration (daily limit, per-request limit).
   - [ ] Implement circuit breaker/failure windows (e.g., trip after N consecutive failures) and emit events when triggered.
   - [ ] Propagate structured errors (`{:error, :budget_exceeded, details}`) to workflows.

4. **Async Delivery via Signal Router**
   - [ ] When `enqueue/2` is used, gateway publishes a `:llm_response` signal (via ADR-0003 router) upon completion.
   - [ ] Provide helper to await responses with correlation IDs, enabling orchestrators to continue other work.

5. **Migration & Testing**
   - [ ] Update actions (GenerateCritique, ReqLLMAction) to depend on the gateway handle rather than `Synapse.ReqLLM`.
   - [ ] Replace `Synapse.TestSupport.FakeReqLLM` with `Synapse.TestSupport.FakeLLMGateway` that implements the same API.
   - [ ] Write integration tests covering budget exhaustion, circuit breaker trips, and async delivery.

6. **Documentation**
   - [ ] Document gateway configuration in `README`/docs (per-profile budgets, provider modules).
   - [ ] Provide runbooks for rotating API keys, resetting budgets, and interpreting gateway telemetry.

## Verification

* No module references `Synapse.ReqLLM` directly; instead, they accept a gateway handle (likely via runtime context).
* Budget exhaustion triggers deterministic errors and telemetry events.
* Async mode successfully publishes responses via Signal Router and orchestrators can await them.

## Risks

* **State explosion:** Gateway tracks budgets and outstanding async requests; memory leaks could occur. Mitigate with TTLs and pruning jobs.
* **Migration complexity:** Many modules currently rely on `Application.put_env`; plan incremental migration (gateway optional at first, fall back to legacy helper until all call sites move).
