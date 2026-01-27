defmodule Synapse.Workflow.Engine do
  @moduledoc """
  Executes declarative workflow specs (see `Synapse.Workflow.Spec`).

  The engine evaluates dependencies, handles step-level retries, emits
  telemetry (`[:synapse, :workflow, :step, :*]`), and surfaces structured
  audit trails for both success and failure scenarios.
  """

  alias Jido.Exec
  alias Synapse.LineageEmitter
  alias Synapse.RunIndex
  alias Synapse.WorkEmitter
  alias Synapse.Workflow.Persistence.Snapshot
  alias Synapse.Workflow.Spec
  alias Synapse.Workflow.Spec.Step
  alias Work.{Error, Job}
  require Logger

  @typedoc "Successful workflow execution payload"
  @type success_t :: %{
          results: map(),
          outputs: map(),
          audit_trail: map()
        }

  @typedoc "Failed workflow execution payload"
  @type failure_t :: %{
          failed_step: atom(),
          error: term(),
          attempts: pos_integer(),
          results: map(),
          audit_trail: map()
        }

  @doc """
  Executes a workflow spec with the provided `:input` and `:context` maps.
  """
  @spec execute(Spec.t(), keyword()) :: {:ok, success_t()} | {:error, failure_t()}
  def execute(%Spec{} = spec, opts \\ []) do
    engine_config = Application.get_env(:synapse, __MODULE__, [])
    persistence_opt = Keyword.get(opts, :persistence, Keyword.get(engine_config, :persistence))
    context = Keyword.get(opts, :context, %{})
    input = Keyword.get(opts, :input, %{})
    persistence = normalize_persistence(persistence_opt)
    request_id = resolve_request_id(context, opts)
    run_id = resolve_run_id(context, opts)
    trace_id = resolve_trace_id(context, run_id)
    plan_id = resolve_plan_id(context, spec)
    work_id = fetch_context_value(context, :work_id)
    context = enrich_context(context, run_id, trace_id, plan_id)
    step_ids = build_step_ids(spec.steps)
    emit_opts = build_emit_opts(opts)

    if persistence && is_nil(request_id) do
      raise ArgumentError,
            "workflow persistence requires a :request_id in the context or options"
    end

    state = %{
      spec: spec,
      input: input,
      context: context,
      remaining_steps: spec.steps,
      completed: MapSet.new(),
      results: %{},
      audit_steps: [],
      started_at: DateTime.utc_now(),
      persistence: persistence,
      request_id: request_id,
      spec_version: spec_version(spec),
      run_id: run_id,
      trace_id: trace_id,
      plan_id: plan_id,
      work_id: work_id,
      step_ids: step_ids,
      step_tracking: %{},
      artifact_refs: [],
      emit_opts: emit_opts
    }

    persist_state(state, :pending)
    emit_run_start(state)

    run(state)
  end

  defp run(%{remaining_steps: [], spec: spec} = state) do
    persist_state(state, :completed)
    emit_run_finish(state, "succeeded")
    {:ok, build_success_response(state, spec.outputs)}
  end

  defp run(%{remaining_steps: remaining} = state) do
    {ready, blocked} = Enum.split_with(remaining, &ready_step?(&1, state.completed))

    cond do
      ready == [] and blocked != [] ->
        raise ArgumentError, "workflow has cyclic or unsatisfied dependencies"

      ready == [] and blocked == [] ->
        run(%{state | remaining_steps: []})

      true ->
        case execute_ready_steps(state, ready) do
          {:ok, updated_state} ->
            run(%{updated_state | remaining_steps: blocked})

          {:error, failed_state, failure} ->
            {:error, finalize_failure(failed_state, failure)}
        end
    end
  end

  defp execute_ready_steps(state, ready_steps) do
    Enum.reduce_while(ready_steps, state, fn step, acc ->
      case execute_step(step, acc) do
        {:ok, updated} -> {:cont, updated}
        {:error, failed_state, failure} -> {:halt, {:error, failed_state, failure}}
      end
    end)
    |> case do
      {:error, failed_state, failure} -> {:error, failed_state, failure}
      updated_state -> {:ok, updated_state}
    end
  end

  defp execute_step(%Step{} = step, state) do
    do_execute_step(step, state, 1)
  end

  defp do_execute_step(step, state, attempt) do
    env = build_env(state, step)
    params = resolve_params(step, env)
    start_dt = DateTime.utc_now()
    {tracking, state} = ensure_step_tracking(state, step)
    {tracking, state} = start_step_emissions(state, step, tracking, params, attempt, start_dt)
    telemetry_meta = telemetry_metadata(state, step, attempt)
    start_monotonic = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:synapse, :workflow, :step, :start],
      %{attempt: attempt},
      telemetry_meta
    )

    exec_context = build_exec_context(state, step, tracking, attempt)
    exec_opts = build_exec_opts(step)

    step_ctx = %{
      state: state,
      step: step,
      tracking: tracking,
      params: params,
      attempt: attempt,
      start_dt: start_dt,
      start_monotonic: start_monotonic,
      telemetry_meta: telemetry_meta
    }

    case Exec.run(step.action, params, exec_context, exec_opts) do
      {:ok, result} -> handle_step_success(step_ctx, result)
      {:error, error} -> handle_step_error(step_ctx, error)
    end
  end

  defp handle_step_success(step_ctx, result) do
    %{
      state: state,
      step: step,
      tracking: tracking,
      params: params,
      attempt: attempt,
      start_dt: start_dt,
      start_monotonic: start_monotonic,
      telemetry_meta: telemetry_meta
    } = step_ctx

    duration = System.monotonic_time(:microsecond) - start_monotonic
    finish_dt = DateTime.utc_now()

    :telemetry.execute(
      [:synapse, :workflow, :step, :stop],
      %{duration_us: duration, attempt: attempt},
      telemetry_meta
    )

    updated_state =
      state
      |> record_success(step, result, attempt, duration, start_dt, finish_dt)
      |> emit_step_success(step, tracking, params, result, attempt, finish_dt)

    persist_state(updated_state, :running, %{last_step_id: step.id, last_attempt: attempt})

    {:ok, updated_state}
  end

  defp handle_step_error(step_ctx, error) do
    %{
      state: state,
      step: step,
      attempt: attempt,
      start_monotonic: start_monotonic,
      telemetry_meta: telemetry_meta
    } = step_ctx

    duration = System.monotonic_time(:microsecond) - start_monotonic
    finish_dt = DateTime.utc_now()

    :telemetry.execute(
      [:synapse, :workflow, :step, :exception],
      %{duration_us: duration, attempt: attempt},
      Map.put(telemetry_meta, :error, error)
    )

    max_attempts = Map.get(step.retry, :max_attempts, 1)

    if attempt < max_attempts do
      do_execute_step(step, state, attempt + 1)
    else
      finalize_step_failure(step_ctx, duration, finish_dt, error)
    end
  end

  defp finalize_step_failure(step_ctx, duration, finish_dt, error) do
    %{
      state: state,
      step: step,
      tracking: tracking,
      params: params,
      attempt: attempt,
      start_dt: start_dt
    } = step_ctx

    failed_state =
      state
      |> record_failure(step, attempt, duration, start_dt, finish_dt, error)
      |> emit_step_failure(step, tracking, params, attempt, finish_dt, error)

    serialized_error = serialize_error(error)

    if step.on_error == :continue do
      updated_state =
        failed_state
        |> put_step_result(step.id, %{status: :error, error: error})
        |> mark_step_completed(step.id)

      persist_state(updated_state, :running, %{
        last_step_id: step.id,
        last_attempt: attempt,
        error: serialized_error
      })

      {:ok, updated_state}
    else
      persist_state(failed_state, :failed, %{
        last_step_id: step.id,
        last_attempt: attempt,
        error: serialized_error
      })

      failure = %{
        failed_step: step.id,
        error: error,
        attempts: attempt
      }

      {:error, failed_state, failure}
    end
  end

  defp build_env(state, step) do
    %{
      input: state.input,
      results: state.results,
      context: state.context,
      step: step,
      workflow: state.spec
    }
  end

  defp resolve_params(step, env) do
    value =
      case step.params do
        nil ->
          %{}

        params when is_map(params) ->
          params

        params when is_list(params) ->
          Map.new(params)

        fun when is_function(fun, 1) ->
          fun.(env)

        fun when is_function(fun, 2) ->
          fun.(env, step)

        other ->
          raise ArgumentError, "invalid params for step #{inspect(step.id)}: #{inspect(other)}"
      end

    normalize_params(step, value)
  end

  defp normalize_params(_step, value) when is_map(value), do: value
  defp normalize_params(_step, value) when is_list(value), do: Map.new(value)

  defp normalize_params(step, _other) do
    raise ArgumentError, "workflow step #{inspect(step.id)} params must resolve to a map"
  end

  defp build_exec_opts(step) do
    step.opts
    |> maybe_put_timeout(step.timeout)
  end

  defp maybe_put_timeout(opts, nil), do: opts

  defp maybe_put_timeout(opts, timeout) do
    if Keyword.has_key?(opts, :timeout) do
      opts
    else
      Keyword.put(opts, :timeout, timeout)
    end
  end

  defp build_exec_context(state, step, tracking, attempt) do
    state.context
    |> Map.merge(step.context || %{})
    |> Map.put_new(:run_id, state.run_id)
    |> Map.put_new(:trace_id, state.trace_id)
    |> maybe_put(:plan_id, state.plan_id)
    |> Map.put(:step_id, tracking.step_id)
    |> Map.put(:work_id, tracking.work_id)
    |> Map.put(:span_id, tracking.span_id)
    |> Map.put(:workflow, state.spec.name)
    |> Map.put(:workflow_metadata, state.spec.metadata)
    |> Map.put(:workflow_step, step.id)
    |> Map.put(:workflow_label, step.label)
    |> Map.put(:workflow_attempt, attempt)
  end

  defp record_success(state, step, result, attempt, duration, started_at, finished_at) do
    audit_entry =
      build_audit_entry(step,
        status: :ok,
        attempts: attempt,
        duration_us: duration,
        started_at: started_at,
        finished_at: finished_at
      )

    %{
      state
      | results: Map.put(state.results, step.id, result),
        completed: MapSet.put(state.completed, step.id),
        audit_steps: [audit_entry | state.audit_steps]
    }
  end

  defp record_failure(state, step, attempt, duration, started_at, finished_at, error) do
    audit_entry =
      build_audit_entry(step,
        status: :error,
        attempts: attempt,
        duration_us: duration,
        started_at: started_at,
        finished_at: finished_at,
        error: error
      )

    %{state | audit_steps: [audit_entry | state.audit_steps]}
  end

  defp put_step_result(state, step_id, value) do
    %{state | results: Map.put(state.results, step_id, value)}
  end

  defp mark_step_completed(state, step_id) do
    %{state | completed: MapSet.put(state.completed, step_id)}
  end

  defp build_audit_entry(step, opts) do
    %{
      step: step.id,
      action: step.action,
      label: step.label,
      description: step.description,
      status: Keyword.fetch!(opts, :status),
      attempts: Keyword.fetch!(opts, :attempts),
      duration_us: Keyword.fetch!(opts, :duration_us),
      started_at: Keyword.fetch!(opts, :started_at),
      finished_at: Keyword.fetch!(opts, :finished_at),
      metadata: step.metadata,
      error: maybe_format_audit_error(Keyword.get(opts, :error))
    }
  end

  defp build_success_response(state, outputs) do
    audit =
      state
      |> wrap_audit_trail(:ok)

    %{
      results: state.results,
      outputs: build_outputs(outputs, state, audit),
      audit_trail: audit
    }
  end

  defp finalize_failure(state, failure) do
    audit = wrap_audit_trail(state, :error)
    emit_run_finish(state, "failed")

    Map.merge(failure, %{
      results: state.results,
      audit_trail: audit
    })
  end

  defp wrap_audit_trail(state, status) do
    %{
      workflow: state.spec.name,
      description: state.spec.description,
      metadata: state.spec.metadata,
      status: status,
      started_at: state.started_at,
      finished_at: DateTime.utc_now(),
      steps: state.audit_steps |> Enum.reverse() |> Enum.map(&sanitize_audit_step/1)
    }
  end

  defp build_outputs(outputs, state, audit) do
    Enum.reduce(outputs, %{}, fn output, acc ->
      value =
        state.results
        |> Map.fetch!(output.from)
        |> maybe_get_path(output.path)
        |> maybe_transform(output.transform, %{state: state, audit: audit})

      Map.put(acc, output.key, value)
    end)
  end

  defp maybe_get_path(value, nil), do: value
  defp maybe_get_path(value, path) when is_list(path), do: get_in(value, path)

  defp maybe_transform(value, nil, _env), do: value
  defp maybe_transform(value, fun, _env) when is_function(fun, 1), do: fun.(value)
  defp maybe_transform(value, fun, env) when is_function(fun, 2), do: fun.(value, env)

  defp ready_step?(%Step{requires: []}, _completed), do: true

  defp ready_step?(%Step{requires: requires}, completed) do
    Enum.all?(requires, &MapSet.member?(completed, &1))
  end

  defp telemetry_metadata(state, step, attempt) do
    %{
      workflow: state.spec.name,
      workflow_description: state.spec.description,
      step: step.id,
      action: step.action,
      label: step.label,
      attempt: attempt,
      run_id: state.run_id,
      trace_id: state.trace_id,
      plan_id: state.plan_id,
      work_id: state.work_id
    }
  end

  defp resolve_run_id(context, opts) do
    Keyword.get(opts, :run_id) || fetch_context_value(context, :run_id) || Ecto.UUID.generate()
  end

  defp resolve_trace_id(context, run_id) do
    fetch_context_value(context, :trace_id) || run_id
  end

  defp resolve_plan_id(context, %Spec{metadata: metadata}) do
    fetch_context_value(context, :plan_id) || fetch_metadata_value(metadata, :plan_id)
  end

  defp fetch_context_value(context, key) when is_map(context) do
    Map.get(context, key) || Map.get(context, to_string(key))
  end

  defp fetch_context_value(_context, _key), do: nil

  defp fetch_metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end

  defp fetch_metadata_value(_metadata, _key), do: nil

  defp enrich_context(context, run_id, trace_id, plan_id) do
    context
    |> Map.put_new(:run_id, run_id)
    |> Map.put_new(:trace_id, trace_id)
    |> maybe_put(:plan_id, plan_id)
  end

  defp build_step_ids(steps) do
    Map.new(steps, fn step ->
      metadata = step.metadata || %{}

      step_id =
        Map.get(metadata, :step_id) || Map.get(metadata, "step_id") || Ecto.UUID.generate()

      {step.id, step_id}
    end)
  end

  defp build_emit_opts(opts) do
    Keyword.take(opts, [
      :lineage_ir,
      :lineage_opts,
      :lineage_include_result,
      :run_index_adapter,
      :run_index_opts,
      :work_adapter,
      :work_opts
    ])
  end

  defp emit_run_start(state) do
    LineageEmitter.emit_trace(state, state.emit_opts)

    _ =
      RunIndex.write_run(
        run_index_run_attrs(state, "running", started_at: state.started_at),
        state.emit_opts
      )

    :ok
  end

  defp emit_run_finish(state, status) do
    finished_at = DateTime.utc_now()

    _ =
      RunIndex.write_run(
        run_index_run_attrs(state, status,
          started_at: state.started_at,
          finished_at: finished_at,
          output_artifact_refs: artifact_refs(state.artifact_refs)
        ),
        state.emit_opts
      )

    :ok
  end

  defp ensure_step_tracking(state, step) do
    case Map.fetch(state.step_tracking, step.id) do
      {:ok, tracking} ->
        {tracking, state}

      :error ->
        step_id = Map.fetch!(state.step_ids, step.id)

        tracking = %{
          step_id: step_id,
          span_id: Ecto.UUID.generate(),
          step_record_id: Ecto.UUID.generate(),
          work_id: Ecto.UUID.generate(),
          work_job: nil,
          started_at: nil
        }

        new_state = put_in(state.step_tracking[step.id], tracking)
        {tracking, new_state}
    end
  end

  defp start_step_emissions(state, step, tracking, params, attempt, started_at) do
    {tracking, state} =
      if is_nil(tracking.started_at) do
        tracking = %{tracking | started_at: started_at}
        job = build_work_job(state, step, tracking, params, started_at)
        tracking = %{tracking | work_job: job}
        state = put_in(state.step_tracking[step.id], tracking)

        LineageEmitter.start_span(step, state, tracking, attempt, state.emit_opts)
        WorkEmitter.emit(:started, job, state.emit_opts)

        {tracking, state}
      else
        {tracking, state}
      end

    _ =
      RunIndex.write_step(
        run_index_step_attrs(
          state,
          step,
          tracking,
          params,
          attempt,
          "running",
          tracking.started_at
        ),
        state.emit_opts
      )

    {tracking, state}
  end

  defp emit_step_success(state, step, tracking, params, result, attempt, finish_dt) do
    {:ok, artifact_ref} =
      LineageEmitter.emit_artifact(step, state, tracking, result, state.emit_opts)

    LineageEmitter.finish_span(step, state, tracking, "succeeded", nil, state.emit_opts)

    job =
      (tracking.work_job ||
         build_work_job(state, step, tracking, %{}, tracking.started_at || finish_dt))
      |> Job.mark_succeeded(result)
      |> Map.put(:completed_at, finish_dt)

    _ = WorkEmitter.emit(:succeeded, job, state.emit_opts)

    _ =
      RunIndex.write_step(
        run_index_step_attrs(
          state,
          step,
          tracking,
          params,
          attempt,
          "succeeded",
          tracking.started_at,
          finished_at: finish_dt,
          output_artifact_refs: artifact_refs([artifact_ref])
        ),
        state.emit_opts
      )

    maybe_add_artifact_ref(state, artifact_ref)
  end

  defp emit_step_failure(state, step, tracking, params, attempt, finish_dt, error) do
    LineageEmitter.finish_span(step, state, tracking, "failed", error, state.emit_opts)

    job =
      (tracking.work_job ||
         build_work_job(state, step, tracking, %{}, tracking.started_at || finish_dt))
      |> Job.mark_failed(work_error(error))
      |> Map.put(:completed_at, finish_dt)

    _ = WorkEmitter.emit(:failed, job, state.emit_opts)

    _ =
      RunIndex.write_step(
        run_index_step_attrs(
          state,
          step,
          tracking,
          params,
          attempt,
          "failed",
          tracking.started_at,
          finished_at: finish_dt
        )
        |> Map.merge(run_index_error_fields(error)),
        state.emit_opts
      )

    state
  end

  defp build_work_job(state, step, tracking, params, started_at) do
    tenant_id = fetch_context_value(state.context, :tenant_id) || "synapse"
    namespace = fetch_context_value(state.context, :namespace) || "default"
    priority = fetch_context_value(state.context, :priority) || :interactive

    Job.new(
      id: tracking.work_id,
      parent_id: state.work_id,
      tenant_id: tenant_id,
      namespace: namespace,
      kind: :workflow_step,
      priority: priority,
      tags: work_tags(state, step),
      payload: build_job_payload(state, step, tracking, params),
      trace_id: to_string(state.trace_id),
      metadata: %{
        workflow: state.spec.name,
        plan_id: state.plan_id,
        run_id: state.run_id,
        step_id: tracking.step_id
      }
    )
    |> Job.mark_running(:synapse, to_string(state.run_id))
    |> Map.put(:started_at, started_at)
    |> Map.put(:span_id, tracking.span_id)
  end

  defp build_job_payload(state, step, tracking, params) do
    %{
      workflow: state.spec.name,
      step_key: step.id,
      step_id: tracking.step_id,
      action: action_name(step.action),
      params: params,
      plan_id: state.plan_id,
      run_id: state.run_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp work_tags(state, step) do
    [:synapse, state.spec.name, step.id]
  end

  defp run_index_run_attrs(state, status, extra) do
    plan_version = plan_version(state.spec.metadata)
    plan_hash = fetch_metadata_value(state.spec.metadata, :plan_hash)
    plan_ref = fetch_metadata_value(state.spec.metadata, :plan_ref)

    base = %{
      id: state.run_id,
      runtime_ref: state.request_id || to_string(state.run_id),
      status: status,
      plan_id: state.plan_id,
      plan_version: plan_version,
      plan_hash: plan_hash,
      plan_ref: plan_ref,
      work_id: state.work_id,
      trace_id: state.trace_id,
      session_id: fetch_context_value(state.context, :session_id),
      actor_type: fetch_context_value(state.context, :actor_type),
      actor_id: fetch_context_value(state.context, :actor_id),
      tenant_id: fetch_context_value(state.context, :tenant_id),
      inputs: state.input,
      labels: fetch_context_value(state.context, :labels),
      started_at: state.started_at
    }

    Map.merge(base, normalize_extra(extra))
  end

  defp run_index_step_attrs(
         state,
         step,
         tracking,
         params,
         attempt,
         status,
         started_at,
         extra \\ %{}
       ) do
    base = %{
      id: tracking.step_record_id,
      run_id: state.run_id,
      step_id: tracking.step_id,
      step_key: step.id,
      action_name: action_name(step.action),
      action_module: inspect(step.action),
      tool_name: nil,
      status: status,
      trace_id: state.trace_id,
      span_id: tracking.span_id,
      work_id: tracking.work_id,
      attempt: attempt,
      max_attempts: Map.get(step.retry, :max_attempts),
      inputs: params,
      started_at: started_at
    }

    Map.merge(base, normalize_extra(extra))
  end

  defp artifact_refs(refs) do
    refs
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&LineageIR.Serialization.to_map/1)
  end

  defp maybe_add_artifact_ref(state, nil), do: state

  defp maybe_add_artifact_ref(state, ref) do
    %{state | artifact_refs: [ref | state.artifact_refs]}
  end

  defp run_index_error_fields(%{__struct__: module} = error) do
    %{
      error_type: inspect(module),
      error_message: Exception.message(error),
      error_details: %{error: inspect(error)}
    }
  end

  defp work_error(%Error{} = error), do: error

  defp work_error(%{__struct__: _} = error) do
    Error.from_exception(error)
  end

  defp normalize_extra(extra) when is_map(extra), do: extra
  defp normalize_extra(extra) when is_list(extra), do: Map.new(extra)

  defp action_name(action) do
    if function_exported?(action, :name, 0), do: action.name(), else: inspect(action)
  end

  defp resolve_request_id(context, opts) do
    Keyword.get(opts, :request_id) || fetch_context_value(context, :request_id)
  end

  defp normalize_persistence(nil), do: nil

  defp normalize_persistence({module, options}) when is_atom(module) and is_list(options),
    do: {module, options}

  defp normalize_persistence(module) when is_atom(module), do: {module, []}

  defp spec_version(%Spec{metadata: metadata}) when is_map(metadata) do
    metadata[:version] || metadata["version"] || 1
  end

  defp spec_version(_), do: 1

  defp plan_version(metadata) when is_map(metadata) do
    metadata[:plan_version] || metadata["plan_version"] || metadata[:version] ||
      metadata["version"]
  end

  defp plan_version(_metadata), do: nil

  defp persist_state(state, status, attrs \\ %{})
  defp persist_state(%{persistence: nil}, _status, _attrs), do: :ok

  defp persist_state(state, status, attrs) do
    {module, options} = state.persistence

    snapshot =
      state
      |> build_snapshot(status, attrs)
      |> sanitize_snapshot()

    case module.upsert_snapshot(snapshot, options) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("workflow snapshot persistence failed #{inspect(reason)}",
          request_id: state.request_id,
          workflow: state.spec.name,
          status: status,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp build_snapshot(state, status, attrs) do
    %Snapshot{
      request_id: state.request_id,
      spec_name: to_string(state.spec.name),
      spec_version: state.spec_version || 1,
      status: status,
      input: state.input,
      context: state.context,
      results: state.results,
      audit_trail: wrap_audit_trail(state, status),
      last_step_id: attrs |> Map.get(:last_step_id) |> normalize_step_id(),
      last_attempt: Map.get(attrs, :last_attempt),
      error: Map.get(attrs, :error)
    }
  end

  defp normalize_step_id(nil), do: nil
  defp normalize_step_id(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_step_id(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp serialize_error(%{__struct__: module} = error) do
    %{type: module, message: Exception.message(error)}
  end

  defp serialize_error(other), do: %{type: :unknown, message: inspect(other)}

  defp maybe_format_audit_error(nil), do: nil
  defp maybe_format_audit_error(error) when is_struct(error), do: serialize_error(error)
  defp maybe_format_audit_error(error), do: error

  defp sanitize_audit_step(entry) do
    Map.update(entry, :error, nil, fn
      nil -> nil
      error when is_struct(error) -> serialize_error(error)
      error -> error
    end)
  end

  defp sanitize_snapshot(%Snapshot{} = snapshot) do
    snapshot
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {key, sanitize_value(value)} end)
    |> Enum.into(%{})
    |> then(&struct(Snapshot, &1))
  end

  defp sanitize_value(%DateTime{} = value), do: value
  defp sanitize_value(%NaiveDateTime{} = value), do: value

  defp sanitize_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> sanitize_value()
  end

  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, sanitize_value(v)} end)
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value
end
