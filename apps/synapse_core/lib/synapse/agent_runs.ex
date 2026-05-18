defmodule Synapse.AgentRuns do
  @moduledoc """
  Product-safe run commands and projections over AppKit AgentIntake.
  """

  alias AppKit.AgentIntake
  alias AppKit.HeadlessSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap, ProductPack}

  @actor_ref "actor:synapse:operator"
  @default_agent_backend Synapse.Fixtures.AgentIntakeBackend
  @default_headless_backend Synapse.Fixtures.HeadlessBackend

  @fixture_runs [
    %{
      id: "fixture-phase-3",
      ref: "run://fixture/phase-3",
      subject_ref: "subject://fixture/phase-3",
      title: "Fixture governed agent run",
      goal_summary: "Exercise AppKit AgentIntake with deterministic product state.",
      state: :awaiting_review,
      surface: "AppKit.AgentIntake",
      authority_state: :authorized,
      budget_state: :within_limit,
      context_pack_ref: "context-pack://fixture/phase-3",
      memory_state: :disabled,
      evidence_refs: ["receipt://fixture/start/phase-3"],
      updated_at: "2026-05-18T03:20:00Z"
    }
  ]

  @spec list_runs(keyword()) :: [map()]
  def list_runs(_opts \\ []), do: @fixture_runs

  @spec fixture_detail(String.t()) :: map()
  def fixture_detail(run_ref_or_id) when is_binary(run_ref_or_id) do
    run =
      Enum.find(@fixture_runs, fn run ->
        run.ref == run_ref_or_id or run.id == run_ref_or_id
      end) || fixture_run(run_ref_or_id)

    Map.merge(run, %{
      turns: [
        %{
          ref: "turn://fixture/#{run.id}/initial",
          kind: :user_input,
          payload_ref: "payload://fixture/#{run.id}/initial",
          status: :accepted
        }
      ],
      events: [
        %{event_ref: "event://fixture/#{run.id}/accepted", kind: :run_started, status: :accepted},
        %{event_ref: "event://fixture/#{run.id}/review", kind: :review_required, status: :pending}
      ],
      controls: [:submit_turn, :refresh, :cancel],
      feature_status: :fixture_backed
    })
  end

  @spec get_run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_run(run_ref_or_id, opts \\ []) when is_binary(run_ref_or_id) do
    config = Config.load(opts)
    context = product_context(config, opts)
    run_ref = normalize_run_ref(run_ref_or_id)

    case HeadlessSurface.run_detail(context, run_ref, %{}, headless_opts(opts)) do
      {:ok, detail} -> {:ok, detail}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_run(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)
    context = product_context(config, opts)
    token = run_token(attrs, opts)
    request = run_request_attrs(config, attrs, context, token)

    with {:ok, future} <- AgentIntake.start_agent_run(context, request, agent_opts(opts)) do
      {:ok, start_view(future, attrs, token)}
    end
  end

  @spec refresh_run(String.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def refresh_run(run_ref_or_id, opts \\ []) when is_binary(run_ref_or_id) do
    config = Config.load(opts)
    context = product_context(config, opts)
    run_ref = normalize_run_ref(run_ref_or_id)

    request = %{
      idempotency_key: "synapse:refresh:#{run_ref}",
      actor_ref: @actor_ref,
      scope_ref: run_ref,
      operations: [:runtime_projection],
      reason: "operator_refresh"
    }

    HeadlessSurface.request_refresh(context, request, headless_opts(opts))
  end

  @spec cancel_run(String.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def cancel_run(run_ref_or_id, opts \\ []) when is_binary(run_ref_or_id) do
    config = Config.load(opts)
    context = product_context(config, opts)
    run_ref = normalize_run_ref(run_ref_or_id)

    AgentIntake.cancel_agent_run(context, run_ref, agent_opts(opts))
  end

  defp start_view(future, attrs, token) do
    %{
      id: token,
      ref: future.run_ref,
      subject_ref: "subject://synapse/#{token}",
      title: string_value(attrs, :title, "Untitled agent run"),
      goal_summary: string_value(attrs, :goal_summary, "No goal summary provided"),
      state: :accepted,
      surface: "AppKit.AgentIntake",
      authority_state: :authorized,
      budget_state: :within_limit,
      context_pack_ref: "context-pack://pending/#{token}",
      memory_state: :disabled,
      evidence_refs: [future.command_ref],
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp run_request_attrs(config, attrs, context, token) do
    trace_id = context.trace_id

    %{
      tenant_ref: "tenant://#{config.tenant_id}",
      installation_ref: "installation://#{config.default_installation_id}",
      subject_ref: "subject://synapse/#{token}",
      actor_ref: @actor_ref,
      profile_bundle: ProductPack.profile_slots(config),
      tool_catalog_ref: "tool-catalog://synapse/default",
      budget_ref: "budget://synapse/default",
      recall_scope_ref: "recall-scope://synapse/project",
      idempotency_key: "synapse:start_run:#{token}",
      trace_id: trace_id,
      correlation_id: "correlation://synapse/#{token}",
      submission_dedupe_key: token,
      initial_input_ref: "payload://synapse/initial/#{token}",
      params: %{
        title: string_value(attrs, :title, "Untitled agent run"),
        goal_summary: string_value(attrs, :goal_summary, "No goal summary provided"),
        team_template_ref: string_value(attrs, :team_template_ref, "standard_implementation")
      }
    }
  end

  defp product_context(%Config{} = config, opts) do
    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    PlatformContext.product_context(config, bootstrap.installation_ref, opts)
  end

  defp agent_opts(opts), do: Keyword.put_new(opts, :backend, @default_agent_backend)
  defp headless_opts(opts), do: Keyword.put_new(opts, :backend, @default_headless_backend)

  defp run_token(attrs, opts) do
    explicit = Keyword.get(opts, :run_token) || map_value(attrs, :run_token)

    cond do
      is_binary(explicit) and explicit != "" -> explicit
      true -> "run-#{System.unique_integer([:positive])}"
    end
  end

  defp normalize_run_ref("run://" <> _rest = ref), do: ref
  defp normalize_run_ref(id), do: "run://fixture/#{id}"

  defp fixture_run(run_ref_or_id) do
    id = run_ref_or_id |> normalize_run_ref() |> String.split("/", trim: true) |> List.last()

    %{
      id: id,
      ref: normalize_run_ref(run_ref_or_id),
      subject_ref: "subject://fixture/#{id}",
      title: "Fixture run #{id}",
      goal_summary: "Fixture detail for #{id}",
      state: :running,
      surface: "AppKit.AgentIntake",
      authority_state: :authorized,
      budget_state: :within_limit,
      context_pack_ref: "context-pack://fixture/#{id}",
      memory_state: :disabled,
      evidence_refs: ["receipt://fixture/start/#{id}"],
      updated_at: "2026-05-18T03:20:00Z"
    }
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
