defmodule Synapse.LineageEmitter do
  @moduledoc false

  require Logger

  alias LineageIR.{Artifact, ArtifactRef, Event, Span, Trace}

  @default_source "synapse"
  @artifact_type "synapse.workflow.step_output"

  def emit_trace(state, opts) do
    if enabled?(opts) do
      trace_id = state.trace_id || state.run_id
      run_id = state.run_id
      work_id = Map.get(state, :work_id)
      plan_id = state.plan_id
      origin_ref = state.request_id || to_string(run_id)

      trace = %Trace{
        id: trace_id,
        root_trace_id: trace_id,
        run_id: run_id,
        work_id: work_id,
        origin: @default_source,
        origin_ref: origin_ref,
        status: "running",
        attributes: trace_attributes(state),
        started_at: utc_now()
      }

      emit_event(
        %Event{
          id: Ecto.UUID.generate(),
          type: "trace_start",
          trace_id: trace_id,
          run_id: run_id,
          work_id: work_id,
          plan_id: plan_id,
          source: @default_source,
          source_ref: origin_ref,
          payload: trace
        },
        opts
      )
    else
      :ok
    end
  end

  def start_span(step, state, tracking, attempt, opts) do
    if enabled?(opts) do
      span_id = tracking.span_id
      trace_id = state.trace_id || state.run_id
      run_id = state.run_id
      work_id = tracking.work_id
      plan_id = state.plan_id

      span = %Span{
        id: span_id,
        trace_id: trace_id,
        run_id: run_id,
        step_id: tracking.step_id,
        work_id: work_id,
        name: span_name(step),
        kind: "workflow_step",
        status: "running",
        attributes: span_attributes(step, state, attempt),
        started_at: tracking.started_at || utc_now()
      }

      emit_event(
        %Event{
          id: Ecto.UUID.generate(),
          type: "span_start",
          trace_id: trace_id,
          span_id: span_id,
          run_id: run_id,
          step_id: tracking.step_id,
          work_id: work_id,
          plan_id: plan_id,
          source: @default_source,
          source_ref: to_string(run_id),
          payload: span
        },
        opts
      )
    else
      :ok
    end
  end

  def finish_span(step, state, tracking, status, error, opts) do
    if enabled?(opts) do
      trace_id = state.trace_id || state.run_id
      run_id = state.run_id
      work_id = tracking.work_id
      plan_id = state.plan_id
      {error_type, error_message, error_details} = error_fields(error)

      span = %Span{
        id: tracking.span_id,
        trace_id: trace_id,
        run_id: run_id,
        step_id: tracking.step_id,
        work_id: work_id,
        name: span_name(step),
        kind: "workflow_step",
        status: status,
        attributes: span_attributes(step, state, nil),
        error_type: error_type,
        error_message: error_message,
        error_details: error_details,
        started_at: tracking.started_at,
        finished_at: utc_now()
      }

      emit_event(
        %Event{
          id: Ecto.UUID.generate(),
          type: "span_end",
          trace_id: trace_id,
          span_id: tracking.span_id,
          run_id: run_id,
          step_id: tracking.step_id,
          work_id: work_id,
          plan_id: plan_id,
          source: @default_source,
          source_ref: to_string(run_id),
          payload: span
        },
        opts
      )
    else
      :ok
    end
  end

  def emit_artifact(step, state, tracking, result, opts) do
    if enabled?(opts) do
      trace_id = state.trace_id || state.run_id
      run_id = state.run_id
      artifact_id = Ecto.UUID.generate()
      include_result? = Keyword.get(opts, :lineage_include_result, true)

      metadata =
        step_metadata(step, state)
        |> maybe_put_result(result, include_result?)

      artifact = %Artifact{
        id: artifact_id,
        trace_id: trace_id,
        span_id: tracking.span_id,
        run_id: run_id,
        step_id: tracking.step_id,
        type: @artifact_type,
        uri: artifact_uri(state, step, artifact_id),
        mime_type: "application/json",
        metadata: metadata,
        created_at: utc_now()
      }

      emit_event(
        %Event{
          id: Ecto.UUID.generate(),
          type: "artifact",
          trace_id: trace_id,
          span_id: tracking.span_id,
          run_id: run_id,
          step_id: tracking.step_id,
          plan_id: state.plan_id,
          source: @default_source,
          source_ref: to_string(run_id),
          payload: artifact
        },
        opts
      )

      ref = %ArtifactRef{
        artifact_id: artifact_id,
        type: artifact.type,
        uri: artifact.uri,
        checksum: artifact.checksum,
        metadata: artifact.metadata
      }

      {:ok, ref}
    else
      {:ok, nil}
    end
  end

  defp enabled?(opts) do
    Keyword.get(opts, :lineage_ir, Application.get_env(:synapse, :lineage_ir, true)) and
      Code.ensure_loaded?(LineageIR.Sink)
  end

  defp emit_event(event, opts) do
    sink_opts = Keyword.get(opts, :lineage_opts, [])

    case LineageIR.Sink.emit(event, sink_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Synapse lineage emit failed: #{inspect(reason)}")
        :ok
    end
  end

  defp span_name(step) do
    if function_exported?(step.action, :name, 0), do: step.action.name(), else: to_string(step.id)
  end

  defp span_attributes(step, state, attempt) do
    action_module = inspect(step.action)

    %{
      "workflow" => to_string(state.spec.name),
      "step_key" => to_string(step.id),
      "action_module" => action_module,
      "action_name" => action_name(step.action),
      "plan_id" => state.plan_id,
      "attempt" => attempt
    }
    |> reject_nil_values()
  end

  defp trace_attributes(state) do
    %{
      "workflow" => to_string(state.spec.name),
      "plan_id" => state.plan_id,
      "request_id" => state.request_id
    }
    |> reject_nil_values()
  end

  defp step_metadata(step, state) do
    %{
      "workflow" => to_string(state.spec.name),
      "step_key" => to_string(step.id),
      "action_name" => action_name(step.action),
      "plan_id" => state.plan_id
    }
    |> reject_nil_values()
  end

  defp artifact_uri(state, step, artifact_id) do
    "synapse://workflow/#{state.run_id}/#{step.id}/#{artifact_id}"
  end

  defp maybe_put_result(metadata, _result, false), do: metadata
  defp maybe_put_result(metadata, result, true), do: Map.put(metadata, "result", result)

  defp error_fields(nil), do: {nil, nil, nil}

  defp error_fields(%{__struct__: module} = error) do
    {inspect(module), Exception.message(error), %{error: inspect(error)}}
  end

  defp error_fields(error) do
    {"error", inspect(error), %{error: inspect(error)}}
  end

  defp action_name(action) do
    if function_exported?(action, :name, 0), do: action.name(), else: inspect(action)
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
