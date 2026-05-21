defmodule Synapse.AgentRuns do
  @moduledoc """
  Product-safe run commands and projections over AppKit AgentIntake.
  """

  alias AppKit.AgentIntake
  alias AppKit.HeadlessSurface
  alias Synapse.{Config, GovernedEffects, PlatformContext, ProductBootstrap, ProductPack}

  @actor_ref "actor:synapse:operator"
  @default_agent_backend Synapse.Fixtures.AgentIntakeBackend
  @default_headless_backend Synapse.Fixtures.HeadlessBackend
  @diagnostic_lanes %{
    "echo" => :echo,
    "probe" => :probe
  }
  @runtime_param_keys [
    :artifact_policy_ref,
    :authority_context_ref,
    :continuation_input,
    :continuation_policy,
    :continue_as_new_turn_threshold,
    :fixture_script,
    :initial_input,
    :max_turns,
    :profile_ref,
    :session_ref,
    :timeout_policy,
    :turn_timeout_ms,
    :worker_ref,
    :workspace_ref
  ]

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

    run
    |> Map.merge(%{
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
    |> maybe_put_staged_live_fixture()
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

    with {:ok, diagnostic_lane} <- diagnostic_lane(attrs, opts) do
      case diagnostic_lane do
        nil ->
          start_default_run(config, context, attrs, token, opts)

        lane ->
          start_diagnostic_run(config, context, attrs, token, lane, opts)
      end
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

  @spec await_run(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def await_run(run_ref_or_id, request \\ %{}, opts \\ [])
      when is_binary(run_ref_or_id) and is_map(request) and is_list(opts) do
    config = Config.load(opts)
    context = product_context(config, opts)
    run_ref = normalize_run_ref(run_ref_or_id)

    AgentIntake.await_agent_outcome(context, run_ref, request, agent_opts(opts))
  end

  defp start_default_run(config, context, attrs, token, opts) do
    request = run_request_attrs(config, attrs, context, token, opts)

    with {:ok, future} <- AgentIntake.start_agent_run(context, request, agent_opts(opts)) do
      {:ok, start_view(future, attrs, token, opts)}
    end
  end

  defp start_diagnostic_run(config, context, attrs, token, diagnostic_lane, opts) do
    case ProductBootstrap.effect_surface_status(opts) do
      %{live?: true} ->
        start_staged_live_run(config, context, attrs, token, diagnostic_lane, opts)

      _status ->
        start_default_run(config, context, attrs, token, opts)
    end
  end

  defp start_staged_live_run(config, context, attrs, token, diagnostic_lane, opts) do
    with {:ok, effect_view} <-
           GovernedEffects.propose_diagnostic_run(context, attrs, token, diagnostic_lane, opts),
         governed_opts <-
           Keyword.merge(opts,
             diagnostic_lane: diagnostic_lane,
             effect_governance_mode: :staging_live,
             governed_effect_refs: effect_view.governed_effect_refs
           ),
         request <- run_request_attrs(config, attrs, context, token, governed_opts) do
      case AgentIntake.start_agent_run(context, request, agent_opts(opts)) do
        {:ok, future} ->
          {:ok, staged_live_view(future, attrs, token, opts, diagnostic_lane, effect_view)}

        {:error, reason} ->
          {:ok, failed_staged_live_view(attrs, token, diagnostic_lane, :run_start_failed, reason)}
      end
    else
      {:error, reason} ->
        {:ok,
         failed_staged_live_view(attrs, token, diagnostic_lane, :effect_proposal_failed, reason)}
    end
  end

  defp start_view(future, attrs, token, opts) do
    %{
      id: token,
      ref: future.run_ref,
      workflow_ref: future.workflow_ref,
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
      feature_status: feature_status(opts),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> maybe_put_governed_effect_refs(future.governed_effect_refs)
  end

  defp staged_live_view(future, attrs, token, opts, diagnostic_lane, effect_view) do
    future
    |> start_view(attrs, token, opts)
    |> Map.merge(%{
      diagnostic_lane: diagnostic_lane,
      effect_governance_mode: :staging_live,
      feature_status: :staging_live,
      governed_effect_refs: effect_view.governed_effect_refs,
      governed_effects: [effect_view],
      evidence_refs:
        [future.command_ref, effect_view.receipt_ref | effect_view.evidence_refs]
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()
    })
  end

  defp failed_staged_live_view(attrs, token, diagnostic_lane, state, reason) do
    %{
      id: token,
      ref: "run://synapse/#{token}",
      subject_ref: "subject://synapse/#{token}",
      title: string_value(attrs, :title, "Untitled agent run"),
      goal_summary: string_value(attrs, :goal_summary, "No goal summary provided"),
      state: state,
      surface: "AppKit.EffectSurface",
      authority_state: :denied,
      budget_state: :within_limit,
      context_pack_ref: "context-pack://pending/#{token}",
      memory_state: :disabled,
      evidence_refs: [],
      feature_status: :staging_live_error,
      diagnostic_lane: diagnostic_lane,
      effect_governance_mode: :staging_live,
      error: %{reason: reason},
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp run_request_attrs(config, attrs, context, token, opts) do
    trace_id = context.trace_id
    runtime_params = runtime_params(opts)

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
      params:
        %{
          title: string_value(attrs, :title, "Untitled agent run"),
          goal_summary: string_value(attrs, :goal_summary, "No goal summary provided"),
          team_template_ref: string_value(attrs, :team_template_ref, "standard_implementation")
        }
        |> Map.merge(runtime_params)
    }
    |> maybe_put(:effect_governance_mode, Keyword.get(opts, :effect_governance_mode))
    |> maybe_put(:diagnostic_lane, Keyword.get(opts, :diagnostic_lane))
    |> maybe_put(:governed_effect_refs, Keyword.get(opts, :governed_effect_refs))
  end

  defp product_context(%Config{} = config, opts) do
    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    PlatformContext.product_context(config, bootstrap.installation_ref, opts)
  end

  defp agent_opts(opts) do
    cond do
      Keyword.has_key?(opts, :backend) ->
        opts

      Keyword.has_key?(opts, :agent_intake_backend) ->
        Keyword.put(opts, :backend, Keyword.fetch!(opts, :agent_intake_backend))

      backend_stack_has?(opts, :agent_intake_backend) ->
        opts

      true ->
        Keyword.put(opts, :backend, @default_agent_backend)
    end
  end

  defp headless_opts(opts), do: Keyword.put_new(opts, :backend, @default_headless_backend)

  defp feature_status(opts),
    do:
      if(Keyword.get(opts, :live_stack?, false),
        do: :live_stack_deterministic,
        else: :fixture_backed
      )

  defp diagnostic_lane(attrs, opts) do
    case Keyword.get(opts, :diagnostic_lane) || map_value(attrs, :diagnostic_lane) do
      nil -> {:ok, nil}
      lane when lane in [:echo, :probe] -> {:ok, lane}
      lane when is_binary(lane) -> Map.fetch(@diagnostic_lanes, lane)
      _other -> {:error, :invalid_diagnostic_lane}
    end
  end

  defp runtime_params(opts) do
    case Keyword.get(opts, :runtime_params, %{}) do
      %{} = params ->
        @runtime_param_keys
        |> Enum.reduce(%{}, fn key, acc ->
          case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
            nil -> acc
            value -> Map.put(acc, key, value)
          end
        end)

      _other ->
        %{}
    end
  end

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

  defp maybe_put_staged_live_fixture(%{id: "staged-live-diagnostic"} = run) do
    effect = staged_live_effect(run.id)

    Map.merge(run, %{
      state: :accepted,
      authority_state: :authorized,
      feature_status: :staging_live,
      diagnostic_lane: :echo,
      effect_governance_mode: :staging_live,
      governed_effect_refs: Map.fetch!(effect, :governed_effect_refs),
      governed_effects: [effect],
      evidence_refs: Map.fetch!(effect, :evidence_refs)
    })
  end

  defp maybe_put_staged_live_fixture(run), do: run

  defp staged_live_effect(token) do
    effect_ref = "effect://synapse/#{token}/echo"

    %{
      effect_ref: effect_ref,
      effect_type: "diagnostic.echo",
      command_ref: "command://synapse/diagnostic/#{token}",
      tenant_ref: "tenant://default",
      actor_ref: @actor_ref,
      installation_ref: "installation://default",
      status: "completed",
      trace_ref: "trace://synapse/diagnostic/#{token}",
      authority_ref: "authority://synapse/effects/diagnostic",
      receipt_ref: "receipt://synapse/effects/diagnostic",
      dispatch_ref: "dispatch://synapse/effects/diagnostic",
      expected_version: 1,
      run_ref: "run://fixture/#{token}",
      trace_summary_hash: "sha256:synapse-diagnostic",
      evidence_refs: ["evidence://synapse/effects/diagnostic"],
      governed_effect_refs: %{
        "effect_ref" => effect_ref,
        "command_ref" => "command://synapse/diagnostic/#{token}",
        "trace_ref" => "trace://synapse/diagnostic/#{token}",
        "authority_ref" => "authority://synapse/effects/diagnostic",
        "receipt_ref" => "receipt://synapse/effects/diagnostic",
        "dispatch_ref" => "dispatch://synapse/effects/diagnostic"
      },
      metadata: %{
        "diagnostic_lane" => "echo",
        "diagnostic_result" => %{"status" => "ok", "summary" => "echo"},
        "product_slug" => "synapse",
        "trace_summary_hash" => "sha256:synapse-diagnostic"
      }
    }
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp backend_stack_has?(opts, key) do
    opts
    |> backend_stacks()
    |> Enum.any?(fn stack ->
      case AppKit.BackendStack.fetch(stack, key) do
        {:ok, nil} -> false
        {:ok, _backend} -> true
        :error -> false
      end
    end)
  end

  defp backend_stacks(opts) do
    [
      Keyword.get(opts, :backend_stack),
      Keyword.get(opts, :app_kit_backend_stack)
    ]
    |> Enum.filter(&match?(%AppKit.BackendStack{}, &1))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_governed_effect_refs(map, refs) when refs == %{}, do: map
  defp maybe_put_governed_effect_refs(map, refs), do: Map.put(map, :governed_effect_refs, refs)
end
