import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :synapse_web, SynapseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "GdiZbGXS3OOk4eD2d4L/1sDYIH872zOofwLM+PB1ltEEBZ93HGQsCRh/2OzQlDUS",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :synapse_web, SynapseWeb.RunNewLive,
  diagnostic_run_opts: [
    backend: Synapse.Fixtures.AgentIntakeBackend,
    effect_surface_adapter: Synapse.Fixtures.EffectSurfaceBackend
  ],
  governed_effect_opts: [effect_surface_adapter: Synapse.Fixtures.EffectSurfaceBackend]

config :synapse_web, SynapseWeb.RunShowLive,
  governed_effect_opts: [effect_surface_adapter: Synapse.Fixtures.EffectSurfaceBackend]

config :synapse_web, SynapseWeb.EvidenceShowLive,
  governed_effects: [
    %{
      effect_ref: "effect://synapse/staged-live-diagnostic/echo",
      effect_type: "diagnostic.echo",
      authority_ref: "authority://synapse/effects/diagnostic",
      receipt_ref: "receipt://synapse/effects/diagnostic",
      run_ref: "run://fixture/staged-live-diagnostic",
      trace_ref: "trace://synapse/diagnostic/staged-live-diagnostic",
      trace_summary_hash: "sha256:synapse-diagnostic",
      evidence_refs: ["evidence://synapse/effects/diagnostic"],
      lifecycle_entries: [
        %{status: "proposed"},
        %{status: "authorized"},
        %{status: "dispatched"},
        %{status: "receipt_received"},
        %{status: "reduced"},
        %{status: "projected"},
        %{status: "completed"}
      ],
      metadata: %{
        "diagnostic_result" => %{"status" => "ok", "summary" => "echo"}
      }
    }
  ]
