defmodule Synapse.Workflow.Engine do
  @moduledoc """
  Executes declarative workflow specs (see `Synapse.Workflow.Spec`).

  The engine evaluates dependencies, handles step-level retries, emits
  telemetry (`[:synapse, :workflow, :step, :*]`), and surfaces structured
  audit trails for both success and failure scenarios.
  """

  alias Jido.Exec
  alias Synapse.Workflow.Persistence.Snapshot
  alias Synapse.Workflow.Spec
  alias Synapse.Workflow.Spec.Step
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
    persistence = normalize_persistence(persistence_opt)
    request_id = resolve_request_id(context, opts)

    if persistence && is_nil(request_id) do
      raise ArgumentError,
            "workflow persistence requires a :request_id in the context or options"
    end

    state = %{
      spec: spec,
      input: Keyword.get(opts, :input, %{}),
      context: context,
      remaining_steps: spec.steps,
      completed: MapSet.new(),
      results: %{},
      audit_steps: [],
      started_at: DateTime.utc_now(),
      persistence: persistence,
      request_id: request_id,
      spec_version: spec_version(spec)
    }

    persist_state(state, :pending)

    run(state)
  end

  defp run(%{remaining_steps: [], spec: spec} = state) do
    persist_state(state, :completed)
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
    telemetry_meta = telemetry_metadata(state, step, attempt)
    start_dt = DateTime.utc_now()
    start_monotonic = System.monotonic_time(:microsecond)

    :telemetry.execute(
      [:synapse, :workflow, :step, :start],
      %{attempt: attempt},
      telemetry_meta
    )

    exec_context = build_exec_context(state, step, attempt)

    case Exec.run(step.action, params, exec_context) do
      {:ok, result} ->
        handle_step_success(
          state,
          step,
          result,
          attempt,
          start_dt,
          start_monotonic,
          telemetry_meta
        )

      {:error, error} ->
        handle_step_error(state, step, attempt, start_dt, start_monotonic, telemetry_meta, error)
    end
  end

  defp handle_step_success(
         state,
         step,
         result,
         attempt,
         start_dt,
         start_monotonic,
         telemetry_meta
       ) do
    duration = System.monotonic_time(:microsecond) - start_monotonic
    finish_dt = DateTime.utc_now()

    :telemetry.execute(
      [:synapse, :workflow, :step, :stop],
      %{duration_us: duration, attempt: attempt},
      telemetry_meta
    )

    updated_state =
      record_success(state, step, result, attempt, duration, start_dt, finish_dt)

    persist_state(updated_state, :running, %{last_step_id: step.id, last_attempt: attempt})

    {:ok, updated_state}
  end

  defp handle_step_error(state, step, attempt, start_dt, start_monotonic, telemetry_meta, error) do
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
      finalize_step_failure(state, step, attempt, duration, start_dt, finish_dt, error)
    end
  end

  defp finalize_step_failure(state, step, attempt, duration, start_dt, finish_dt, error) do
    failed_state =
      record_failure(state, step, attempt, duration, start_dt, finish_dt, error)

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

  defp build_exec_context(state, step, attempt) do
    state.context
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
      attempt: attempt
    }
  end

  defp resolve_request_id(context, opts) do
    Keyword.get(opts, :request_id) || Map.get(context, :request_id) ||
      Map.get(context, "request_id")
  end

  defp normalize_persistence(nil), do: nil

  defp normalize_persistence({module, options}) when is_atom(module) and is_list(options),
    do: {module, options}

  defp normalize_persistence(module) when is_atom(module), do: {module, []}

  defp spec_version(%Spec{metadata: metadata}) when is_map(metadata) do
    metadata[:version] || metadata["version"] || 1
  end

  defp spec_version(_), do: 1

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
