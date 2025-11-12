defmodule Synapse.Orchestrator.Actions.RunConfig do
  @moduledoc """
  Executes orchestrator-managed actions through the `Synapse.Workflow.Engine` so
  every agent run benefits from telemetry and persistence.
  """

  use Jido.Action,
    name: "synapse_run_config",
    description: "Executes orchestrator-managed actions and emits results",
    schema: [
      _config: [type: :any, required: true],
      _router: [type: {:or, [:atom, {:in, [nil]}]}, default: nil],
      _emits: [type: {:list, :atom}, default: []]
    ]

  require Logger

  alias Synapse.Orchestrator.AgentConfig
  alias Synapse.Signal
  alias Synapse.SignalRouter
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step

  @orchestrator_defaults %{
    reviews: %{},
    stats: %{total: 0, fast_path: 0, deep_review: 0, completed: 0}
  }

  @impl true
  def run(%{_config: %AgentConfig{type: :orchestrator} = config} = params, _context) do
    run_orchestrator(config, params)
  rescue
    error ->
      log_crash(error, __STACKTRACE__)
      {:error, error}
  end

  def run(params, _context) do
    run_specialist(params)
  rescue
    error ->
      log_crash(error, __STACKTRACE__)
      {:error, error}
  end

  defp build_result(%{result_builder: builder} = config, results, signal_payload) do
    cond do
      is_function(builder, 3) ->
        builder.(results, signal_payload, config)

      is_function(builder, 2) ->
        builder.(results, signal_payload)

      match?({m, f, a} when is_atom(m) and is_atom(f) and is_list(a), builder) ->
        {m, f, a} = builder
        apply(m, f, [results, signal_payload | a])

      true ->
        %{
          config_id: config.id,
          signal: signal_payload,
          results: results
        }
    end
  end

  defp maybe_emit_signal(nil, _emits, _config_id, _result), do: :ok
  defp maybe_emit_signal(_router, [], _config_id, _result), do: :ok

  defp maybe_emit_signal(router, emits, config_id, result) do
    Enum.each(emits, fn topic ->
      try do
        case SignalRouter.publish(
               router,
               topic,
               result,
               source: "/synapse/agents/#{config_id}",
               subject: "synapse://agents/#{config_id}"
             ) do
          {:ok, _signal} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to publish orchestrator result",
              router: router,
              topic: topic,
              reason: inspect(reason)
            )
        end
      rescue
        error ->
          Logger.error("""
          Failed to publish orchestrator result
          topic=#{inspect(topic)} router=#{inspect(router)} config=#{config_id}
          payload=#{inspect(result)}
          #{Exception.format(:error, error, __STACKTRACE__)}
          """)
      end
    end)
  end

  defp build_workflow_spec([]) do
    %{
      spec: nil,
      steps: []
    }
  end

  defp build_workflow_spec(actions) do
    steps =
      actions
      |> Enum.with_index(1)
      |> Enum.map(fn {action, index} ->
        step_id = :"action_#{index}"

        %{
          id: step_id,
          module: action,
          step:
            Step.new(
              id: step_id,
              action: action,
              label: Module.split(action) |> List.last(),
              params: fn env -> env.input end,
              on_error: :continue
            )
        }
      end)

    spec =
      Spec.new(
        name: :orchestrator_run_config,
        metadata: %{version: 1, actions: actions},
        steps: Enum.map(steps, & &1.step),
        outputs: []
      )

    %{spec: spec, steps: steps}
  end

  defp normalize_results(step_defs, results_map) do
    Enum.map(step_defs, fn %{id: id, module: module} ->
      entry = Map.get(results_map, id)

      cond do
        match?(%{status: :error}, entry) ->
          {:error, module, Map.get(entry, :error)}

        true ->
          {:ok, module, entry}
      end
    end)
  end

  defp normalize_config(%AgentConfig{} = config), do: config

  defp normalize_config(config) when is_map(config) do
    struct!(AgentConfig, config)
  end

  defp generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end

  defp run_specialist(params) do
    config = params |> Map.fetch!(:_config) |> normalize_config()
    router = Map.get(params, :_router)
    emits = Map.get(params, :_emits, config.signals.emits || [])

    signal_payload =
      params
      |> Map.drop([:_config, :_router, :_emits, :_signal, :_state])

    spec_info = build_workflow_spec(config.actions)

    request_id =
      Map.get(signal_payload, :request_id) ||
        generate_request_id()

    if spec_info.spec do
      case Engine.execute(spec_info.spec,
             input: signal_payload,
             context: %{request_id: request_id, agent_id: config.id}
           ) do
        {:ok, exec} ->
          action_results = normalize_results(spec_info.steps, exec.results)
          result_data = build_result(config, action_results, signal_payload)

          maybe_emit_signal(router, emits, config.id, result_data)

          {:ok,
           %{
             results: action_results,
             result: result_data,
             audit_trail: exec.audit_trail,
             emitted?: router && emits != []
           }}

        {:error, failure} ->
          Logger.error("Orchestrator workflow failed",
            agent_id: config.id,
            reason: inspect(failure.error),
            failed_step: failure.failed_step
          )

          {:error, failure.error}
      end
    else
      result_data = build_result(config, [], signal_payload)
      maybe_emit_signal(router, emits, config.id, result_data)

      {:ok,
       %{
         results: [],
         result: result_data,
         audit_trail: %{
           workflow: :orchestrator_run_config,
           status: :ok,
           steps: []
         },
         emitted?: router && emits != []
       }}
    end
  end

  defp run_orchestrator(config, params) do
    router = Map.get(params, :_router)
    state = Map.get(params, :_state) || @orchestrator_defaults
    signal = Map.get(params, :_signal)
    emits = Map.get(params, :_emits, config.signals.emits || [])
    orchestration = Map.get(config, :orchestration) || %{}

    cond do
      is_nil(signal) ->
        {:ok, %{state: state}}

      signal.type == Signal.type(:review_request) ->
        handle_orchestrator_request(config, orchestration, state, signal, router, emits)

      signal.type == Signal.type(:review_result) ->
        handle_orchestrator_result(config, orchestration, state, signal, router)

      true ->
        {:ok, %{state: state}}
    end
  end

  defp handle_orchestrator_request(config, orchestration, state, signal, router, emits) do
    state = ensure_orchestrator_state(state)
    _review_id = Map.get(signal.data, :review_id) || Map.get(signal.data, "review_id")
    review_data = Map.new(signal.data)
    classify_fn = Map.get(orchestration, :classify_fn)

    unless is_function(classify_fn) or match?({_, _, _}, classify_fn) do
      raise ArgumentError, ":classify_fn is required in orchestration config"
    end

    classification = call_callable(classify_fn, [review_data])
    path = classification_path(classification)

    state =
      state
      |> increment_stat(:total)

    case path do
      :fast_path ->
        handle_fast_path(
          config,
          orchestration,
          state,
          review_data,
          classification,
          signal,
          router,
          emits
        )

      _ ->
        handle_deep_review(
          config,
          orchestration,
          state,
          review_data,
          classification,
          signal,
          router
        )
    end
  end

  defp handle_fast_path(
         config,
         orchestration,
         state,
         review_data,
         classification,
         signal,
         router,
         emits
       ) do
    fast_path_fn = Map.get(orchestration, :fast_path_fn)
    state = increment_stat(state, :fast_path)

    review_state =
      build_review_state(signal, classification, [])
      |> Map.put(:review_data, review_data)

    summary = build_summary(orchestration, [], review_state)
    publish_summary(router, config.id, summary, review_state.review_id)
    emit_summary_telemetry(config.id, summary)
    maybe_emit_signal(router, emits, config.id, summary)

    if fast_path_fn do
      call_callable(fast_path_fn, [signal, router])
    end

    {:ok, %{state: state}}
  end

  defp handle_deep_review(
         config,
         orchestration,
         state,
         review_data,
         classification,
         signal,
         router
       ) do
    spawn_spec = Map.get(orchestration, :spawn_specialists)
    specialists = resolve_specialists(spawn_spec, review_data, classification)

    review_state =
      build_review_state(signal, classification, specialists)
      |> Map.put(:review_data, review_data)

    updated_state =
      state
      |> increment_stat(:deep_review)
      |> put_in([:reviews, review_state.review_id], review_state)

    if specialists == [] do
      complete_review(config, orchestration, updated_state, review_state.review_id, router)
    else
      {:ok, %{state: updated_state}}
    end
  end

  defp handle_orchestrator_result(config, orchestration, state, signal, router) do
    state = ensure_orchestrator_state(state)
    result = Map.new(signal.data)
    review_id = Map.get(result, :review_id) || Map.get(result, "review_id")

    case get_in(state, [:reviews, review_id]) do
      nil ->
        {:ok, %{state: state}}

      review_state ->
        negotiated_state =
          maybe_negotiate(Map.get(orchestration, :negotiate_fn), review_state, result)

        updated_state =
          state
          |> put_in([:reviews, review_id], update_review_state(negotiated_state, result))

        pending = get_in(updated_state, [:reviews, review_id, :pending])

        if pending == [] do
          complete_review(config, orchestration, updated_state, review_id, router)
        else
          {:ok, %{state: updated_state}}
        end
    end
  end

  defp complete_review(config, orchestration, state, review_id, router) do
    case get_in(state, [:reviews, review_id]) do
      nil ->
        {:ok, %{state: state}}

      review_state ->
        duration_ms = duration_ms(review_state.started_at)

        review_state =
          review_state
          |> Map.update(:metadata, %{}, fn metadata ->
            metadata
            |> Map.put(:duration_ms, duration_ms)
            |> Map.put(
              :specialists_resolved,
              Enum.uniq(review_state.metadata.specialists_resolved)
            )
          end)

        results = Enum.reverse(review_state.results)
        summary = build_summary(orchestration, results, review_state)

        publish_summary(router, config.id, summary, review_id)
        emit_summary_telemetry(config.id, summary)
        maybe_emit_signal(router, config.signals.emits || [], config.id, summary)

        updated_state =
          state
          |> update_in([:reviews], &Map.delete(&1, review_id))
          |> increment_stat(:completed)

        {:ok, %{state: updated_state}}
    end
  end

  defp build_review_state(signal, classification, specialists) do
    %{
      review_id: Map.get(signal.data, :review_id) || Map.get(signal.data, "review_id"),
      classification: classification,
      classification_path: classification_path(classification),
      pending: Enum.map(specialists, &normalize_specialist_id/1),
      results: [],
      started_at: System.monotonic_time(:millisecond),
      signal: signal,
      metadata: %{
        decision_path: classification_path(classification),
        specialists_resolved: [],
        duration_ms: 0,
        negotiations: []
      }
    }
  end

  defp update_review_state(review_state, result) do
    agent = result_agent(result)

    review_state
    |> update_in([:results], &[result | &1])
    |> update_in([:pending], fn pending -> Enum.reject(pending, &(&1 == agent)) end)
    |> update_in([:metadata, :specialists_resolved], &[agent | &1])
  end

  defp ensure_orchestrator_state(state) do
    state
    |> Map.put_new(:reviews, %{})
    |> Map.put_new(:stats, %{total: 0, fast_path: 0, deep_review: 0, completed: 0})
  end

  defp increment_stat(state, key) do
    update_in(state, [:stats, key], fn
      nil -> 1
      value -> value + 1
    end)
  end

  defp classification_path(%{path: path}) when is_binary(path), do: String.to_atom(path)
  defp classification_path(%{path: path}) when is_atom(path), do: path
  defp classification_path(_), do: :deep_review

  defp resolve_specialists(nil, _review_data, _classification), do: []

  defp resolve_specialists(list, _review_data, _classification) when is_list(list) do
    Enum.map(list, &normalize_specialist_id/1)
  end

  defp resolve_specialists(callable, review_data, classification) do
    callable
    |> call_callable([review_data, classification])
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_specialist_id/1)
  end

  defp call_callable({module, fun, extra_args}, args) do
    apply(module, fun, args ++ extra_args)
  end

  defp call_callable(fun, args) when is_function(fun) do
    arity =
      case :erlang.fun_info(fun, :arity) do
        {:arity, value} when is_integer(value) -> value
        _ -> length(args)
      end

    apply(fun, Enum.take(args, arity))
  end

  defp call_callable(nil, _args), do: nil

  defp normalize_specialist_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_specialist_id(id) when is_binary(id), do: id
  defp normalize_specialist_id(other), do: to_string(other)

  defp build_summary(orchestration, results, review_state) do
    aggregation_fn = Map.get(orchestration, :aggregation_fn)

    unless is_function(aggregation_fn) or match?({_, _, _}, aggregation_fn) do
      raise ArgumentError, ":aggregation_fn is required in orchestration config"
    end

    summary =
      call_callable(aggregation_fn, [results, review_state])
      |> ensure_summary_metadata(review_state)

    if is_map(summary) do
      summary
    else
      raise ArgumentError, ":aggregation_fn must return a map conforming to review.summary schema"
    end
  end

  defp ensure_summary_metadata(summary, review_state) when is_map(summary) do
    metadata =
      summary
      |> Map.get(:metadata, %{})
      |> Map.put_new(:decision_path, review_state.classification_path)

    Map.put(summary, :metadata, metadata)
  end

  defp ensure_summary_metadata(summary, _review_state), do: summary

  defp publish_summary(router, config_id, summary, review_id) do
    case SignalRouter.publish(
           router,
           :review_summary,
           summary,
           source: "/synapse/agents/#{config_id}",
           subject: "synapse://agents/#{config_id}/review/#{review_id}"
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish review summary",
          router: router,
          config: config_id,
          reason: inspect(reason)
        )
    end
  end

  defp duration_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp result_agent(result) do
    result[:agent] || result["agent"] || "unknown"
  end

  defp maybe_negotiate(nil, review_state, _result), do: review_state

  defp maybe_negotiate(callback, review_state, result) do
    case call_callable(callback, [result, review_state]) do
      {:ok, new_state} when is_map(new_state) -> new_state
      new_state when is_map(new_state) -> new_state
      _ -> review_state
    end
  end

  defp emit_summary_telemetry(config_id, summary) do
    metadata = Map.get(summary, :metadata, %{})
    duration_ms = metadata[:duration_ms] || metadata["duration_ms"] || 0
    specialists = metadata[:specialists_resolved] || metadata["specialists_resolved"] || []
    negotiations = metadata[:negotiations] || metadata["negotiations"] || []
    findings = Map.get(summary, :findings, []) || []
    recommendations = Map.get(summary, :recommendations, []) || []

    measurements = %{
      duration_ms: duration_ms,
      finding_count: length(findings),
      recommendation_count: length(recommendations)
    }

    event_metadata = %{
      config_id: config_id,
      review_id: Map.get(summary, :review_id) || Map.get(summary, "review_id"),
      status: Map.get(summary, :status, :unknown) || :unknown,
      severity: Map.get(summary, :severity, :none) || :none,
      decision_path: metadata[:decision_path] || metadata["decision_path"],
      specialists: specialists,
      escalations: Map.get(summary, :escalations, []) || [],
      negotiations: negotiations
    }

    :telemetry.execute(
      [:synapse, :workflow, :orchestrator, :summary],
      measurements,
      event_metadata
    )
  rescue
    error ->
      Logger.warning("Failed to emit orchestrator summary telemetry",
        config_id: config_id,
        summary: Map.take(summary, [:review_id, :status, :severity]),
        reason: Exception.message(error)
      )
  end

  defp log_crash(error, stacktrace) do
    Logger.error("""
    RunConfig crashed
    #{Exception.format(:error, error, stacktrace)}
    """)
  end
end
