defmodule Synapse.AgentRuns do
  @moduledoc """
  Product-safe durable run acceptance and readback through AppKit.

  Synapse owns presentation and request intent only. The injected AppKit
  backend stack owns acceptance, snapshots, cursors, and workflow truth.
  """

  alias AppKit.{AgentIntake, HeadlessSurface}

  alias AppKit.Core.AgentIntake.{
    AgentRunCursor,
    AgentRunEventPage,
    RunOutcomeFuture
  }

  alias AppKit.Core.RuntimeReadback.{
    CommandResult,
    RuntimeRow,
    RuntimeRunDetail,
    RuntimeStateSnapshot
  }

  alias Synapse.{Config, PlatformContext, ProductBootstrap, ProductPack}

  @actor_ref "actor:synapse:operator"
  @durable_control_actions [:pause, :resume, :cancel, :retry, :supersede]

  @spec list_runs(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_runs(opts \\ []) when is_list(opts) do
    with {:ok, config, context} <- product_context(opts),
         {:ok, runtime_opts} <- ProductBootstrap.durable_readback_options(opts),
         {:ok, %RuntimeStateSnapshot{} = snapshot} <-
           HeadlessSurface.state_snapshot(context, %{}, runtime_opts),
         :ok <- durable_posture(snapshot.persistence_posture) do
      {:ok, Enum.map(snapshot.rows, &list_view(&1, config))}
    else
      {:ok, _other} -> {:error, :invalid_durable_run_snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_run(run_ref_or_id, opts \\ [])
      when is_binary(run_ref_or_id) and is_list(opts) do
    run_ref = decode_run_ref(run_ref_or_id)

    with {:ok, config, context} <- product_context(opts),
         {:ok, runtime_opts} <- ProductBootstrap.durable_readback_options(opts),
         {:ok, %RuntimeRunDetail{runtime_row: %RuntimeRow{}} = snapshot} <-
           HeadlessSurface.run_detail(context, run_ref, %{}, runtime_opts),
         :ok <- durable_posture(snapshot.persistence_posture),
         {:ok, cursor} <- cursor_for(run_ref, config, opts),
         {:ok, %AgentRunEventPage{} = event_page} <-
           AgentIntake.catch_up_agent_events(context, cursor, runtime_opts) do
      {:ok, detail_view(snapshot, event_page)}
    else
      {:ok, _other} -> {:error, :invalid_durable_run_snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_run(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    token = run_token(attrs, opts)

    with {:ok, config, context} <- product_context(opts),
         {:ok, runtime_opts} <- ProductBootstrap.agent_intake_options(opts),
         request <- run_request_attrs(config, attrs, context, token),
         {:ok, %RunOutcomeFuture{accepted?: true} = future} <-
           AgentIntake.start_agent_run(context, request, runtime_opts) do
      {:ok, acceptance_view(future, attrs, token)}
    else
      {:ok, %RunOutcomeFuture{accepted?: false}} -> {:error, :run_not_accepted}
      {:ok, _other} -> {:error, :invalid_run_acceptance}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec refresh_run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def refresh_run(run_ref_or_id, opts \\ []), do: get_run(run_ref_or_id, opts)

  @spec cancel_run(String.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def cancel_run(run_ref_or_id, opts \\ [])
      when is_binary(run_ref_or_id) and is_list(opts) do
    control_run(
      run_ref_or_id,
      :cancel,
      %{expected_control_row_version: Keyword.get(opts, :expected_control_row_version)},
      opts
    )
  end

  @spec control_run(String.t(), atom(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def control_run(run_ref_or_id, action, params, opts \\ [])

  def control_run(run_ref_or_id, action, params, opts)
      when is_binary(run_ref_or_id) and action in @durable_control_actions and is_map(params) and
             is_list(opts) do
    run_ref = decode_run_ref(run_ref_or_id)

    with {:ok, expected_version} <- expected_control_version(params),
         idempotency_key <- control_idempotency_key(run_ref, action, expected_version, params),
         {:ok, runtime_opts} <- ProductBootstrap.durable_readback_options(opts),
         context_opts <-
           control_context_options(opts, runtime_opts, idempotency_key, run_ref, action),
         {:ok, _config, context} <- product_context(context_opts),
         {:ok, %CommandResult{} = result} <-
           HeadlessSurface.request_control(
             context,
             %{
               idempotency_key: idempotency_key,
               actor_ref: context.actor_ref.id,
               run_ref: run_ref,
               action: action,
               params: Map.put(params, :expected_control_row_version, expected_version)
             },
             runtime_opts
           ) do
      {:ok, result}
    else
      {:ok, _other} -> {:error, :invalid_durable_control_result}
      {:error, reason} -> {:error, reason}
    end
  end

  def control_run(_run_ref_or_id, _action, _params, _opts),
    do: {:error, :invalid_durable_control_request}

  @spec await_run(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def await_run(run_ref_or_id, request \\ %{}, opts \\ [])
      when is_binary(run_ref_or_id) and is_map(request) and is_list(opts) do
    with {:ok, _config, context} <- product_context(opts),
         {:ok, runtime_opts} <- ProductBootstrap.agent_intake_options(opts) do
      AgentIntake.await_agent_outcome(
        context,
        decode_run_ref(run_ref_or_id),
        request,
        runtime_opts
      )
    end
  end

  defp product_context(opts) do
    config = Config.load(opts)

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)) do
      {:ok, config, PlatformContext.product_context(config, bootstrap.installation_ref, opts)}
    end
  end

  defp run_request_attrs(config, attrs, context, token) do
    %{
      tenant_ref: "tenant://#{config.tenant_id}",
      installation_ref: "installation://#{config.default_installation_id}",
      subject_ref: "subject://synapse/#{token}",
      actor_ref: @actor_ref,
      profile_bundle: ProductPack.profile_slots(config),
      tool_catalog_ref: "tool-catalog://synapse/default",
      budget_ref: "budget://synapse/default",
      recall_scope_ref: "recall-scope://synapse/project",
      idempotency_key: "synapse:start-run:#{token}",
      trace_id: context.trace_id,
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

  defp acceptance_view(future, attrs, token) do
    %{
      id: route_id(future.run_ref),
      ref: future.run_ref,
      workflow_ref: future.workflow_ref,
      command_ref: future.command_ref,
      correlation_id: future.correlation_id,
      title: string_value(attrs, :title, "Untitled agent run"),
      goal_summary: string_value(attrs, :goal_summary, "No goal summary provided"),
      subject_ref: "subject://synapse/#{token}",
      state: :accepted,
      surface: "AppKit.AgentIntake",
      feature_status: :durable_acceptance,
      polling_hint: future.polling_hint
    }
  end

  defp list_view(row, _config) do
    control = control_view(extension(row.extensions, :control))

    %{
      id: route_id(row.run_ref),
      ref: row.run_ref,
      subject_ref: row.subject_ref,
      workflow_ref: row.workflow_ref,
      title: extension(row.extensions, :title) || row.run_ref,
      state: row.state,
      status_reason: row.status_reason,
      surface: "AppKit.AgentIntake",
      updated_at: row.updated_at,
      persistence_posture: row.persistence_posture,
      control: control,
      control_state: control.state
    }
  end

  defp detail_view(snapshot, event_page) do
    row = snapshot.runtime_row
    extensions = if row, do: row.extensions, else: %{}
    control = control_view(extension(extensions, :control))

    %{
      id: route_id(snapshot.run_ref),
      ref: snapshot.run_ref,
      subject_ref: if(row, do: row.subject_ref, else: nil),
      workflow_ref: if(row, do: row.workflow_ref, else: nil),
      title: extension(extensions, :title) || snapshot.run_ref,
      goal_summary:
        extension(extensions, :goal_summary) ||
          if(row, do: row.status_reason, else: nil),
      state: if(row, do: row.state, else: :accepted),
      surface: "AppKit.AgentIntake",
      feature_status: :durable_snapshot,
      budget_state: snapshot.budget_state,
      turns: snapshot.turns,
      events: event_page.events,
      cursor: event_page.cursor,
      has_more_events?: event_page.has_more?,
      next_cursor_ref: event_page.next_cursor_ref,
      persistence_posture: snapshot.persistence_posture,
      updated_at: if(row, do: row.updated_at, else: nil),
      control: control,
      control_state: control.state,
      ambiguous?: control.state in ["outcome_unknown", "reconciling"],
      degraded?: control.state in ["outcome_unknown", "reconciling", "operator_required"],
      available_controls: available_controls(control.state)
    }
  end

  @control_fields [
    :state,
    :generation,
    :attempt_sequence,
    :sequence,
    :row_version,
    :attempt_ref,
    :generation_ref,
    :external_operation_ref,
    :deadline_at,
    :fence_epoch,
    :reconciliation_attempts,
    :reconcile_owner,
    :reconcile_lease_expires_at,
    :next_reconcile_at,
    :terminal_receipt_ref,
    :last_error,
    :updated_at
  ]

  defp control_view(control) when is_map(control) do
    Map.new(@control_fields, fn field -> {field, map_value(control, field)} end)
  end

  defp control_view(_control), do: Map.new(@control_fields, &{&1, nil})

  defp available_controls("accepted"), do: [:cancel, :supersede]
  defp available_controls("running"), do: [:pause, :cancel, :supersede]
  defp available_controls("paused"), do: [:resume, :cancel, :supersede]
  defp available_controls("pause_requested"), do: [:cancel]
  defp available_controls("resume_requested"), do: [:cancel]
  defp available_controls("failed"), do: [:retry, :supersede]
  defp available_controls("operator_required"), do: [:retry, :cancel, :supersede]
  defp available_controls(_state), do: []

  defp expected_control_version(params) do
    case map_value(params, :expected_control_row_version) do
      version when is_integer(version) and version > 0 -> {:ok, version}
      _other -> {:error, :invalid_expected_control_row_version}
    end
  end

  defp control_idempotency_key(run_ref, action, expected_version, params) do
    token =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({run_ref, action, expected_version, params})
      )
      |> Base.url_encode64(padding: false)

    "synapse:control:#{action}:#{expected_version}:#{token}"
  end

  defp control_context_options(opts, runtime_opts, idempotency_key, run_ref, action) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({run_ref, action, idempotency_key}))
    request_token = Base.url_encode64(digest, padding: false)
    trace_id = digest |> Base.encode16(case: :lower) |> binary_part(0, 32)

    runtime_opts
    |> Keyword.take([:control_authority_ref, :control_permission_decision_ref])
    |> Keyword.merge(opts)
    |> Keyword.put(:idempotency_key, idempotency_key)
    |> Keyword.put(:request_id, "request://synapse/control/#{request_token}")
    |> Keyword.put_new(:trace_id, trace_id)
  end

  defp cursor_for(run_ref, config, opts) do
    case Keyword.get(opts, :cursor) do
      %AgentRunCursor{} = cursor ->
        {:ok, cursor}

      nil ->
        AgentRunCursor.new(%{
          cursor_ref: "cursor://synapse/#{Base.url_encode64(run_ref, padding: false)}",
          ledger_ref: run_ref,
          tenant_ref: "tenant://#{config.tenant_id}",
          actor_ref: @actor_ref,
          last_seq_seen: 0,
          visibility: :product
        })

      _other ->
        {:error, :invalid_run_cursor}
    end
  end

  defp durable_posture(%{durable?: true}), do: :ok
  defp durable_posture(_posture), do: {:error, :durable_run_projection_unavailable}

  defp run_token(attrs, opts) do
    case Keyword.get(opts, :run_token) || map_value(attrs, :run_token) do
      value when is_binary(value) and value != "" -> value
      _other -> "run-#{System.unique_integer([:positive])}"
    end
  end

  defp decode_run_ref(value) do
    case URI.decode_www_form(value) do
      "" -> value
      decoded -> decoded
    end
  rescue
    ArgumentError -> value
  end

  defp route_id(run_ref), do: URI.encode_www_form(run_ref)

  defp extension(extensions, key) when is_map(extensions),
    do: Map.get(extensions, key, Map.get(extensions, Atom.to_string(key)))

  defp extension(_extensions, _key), do: nil

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
