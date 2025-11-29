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
    tasks: %{},
    stats: %{total: 0, routed: 0, dispatched: 0, completed: 0, failed: 0}
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
    state = Map.get(params, :_state) || initial_state(config)
    signal = Map.get(params, :_signal)
    emits = Map.get(params, :_emits, config.signals.emits || [])
    orchestration = Map.get(config, :orchestration) || %{}
    roles = get_signal_roles(config)
    request_type = role_type(roles.request)
    result_type = role_type(roles.result)

    cond do
      is_nil(signal) ->
        {:ok, %{state: state}}

      not is_nil(request_type) and signal.type == request_type ->
        handle_orchestrator_request(config, orchestration, state, signal, router, emits, roles)

      not is_nil(result_type) and signal.type == result_type ->
        handle_orchestrator_result(config, orchestration, state, signal, router, roles)

      true ->
        {:ok, %{state: state}}
    end
  end

  defp role_type(nil), do: nil
  defp role_type(topic), do: Signal.type(topic)

  defp get_signal_roles(config) do
    signals = Map.get(config, :signals, %{})

    roles =
      case Map.get(signals, :roles) do
        %{} = roles ->
          merge_roles_with_defaults(roles)

        _ ->
          infer_roles_from_signals(signals)
      end

    merge_roles_with_defaults(roles)
  end

  defp merge_roles_with_defaults(roles) do
    Enum.reduce(default_roles(), %{}, fn {role, default_topic}, acc ->
      topic = Map.get(roles, role) || default_topic
      Map.put(acc, role, topic)
    end)
  end

  defp default_roles do
    %{
      request: :task_request,
      result: :task_result,
      summary: :task_summary
    }
  end

  defp infer_roles_from_signals(%{subscribes: subscribes, emits: emits}) do
    %{
      request: find_role_topic(subscribes, ["task_request", "review_request", "request"]),
      result: find_role_topic(subscribes, ["task_result", "review_result", "result"]),
      summary:
        find_role_topic(emits, ["task_summary", "review_summary", "summary"]) || List.first(emits)
    }
  end

  defp find_role_topic(topics, suffixes) when is_list(topics) do
    Enum.find(topics, fn topic ->
      topic_str = Atom.to_string(topic)
      Enum.any?(suffixes, &String.ends_with?(topic_str, &1))
    end)
  end

  defp find_role_topic(_topics, _suffixes), do: nil

  defp handle_orchestrator_request(config, orchestration, state, signal, router, emits, roles) do
    state = ensure_orchestrator_state(state)
    task_data = Map.new(signal.data)
    classify_fn = Map.get(orchestration, :classify_fn)

    unless is_function(classify_fn) or match?({_, _, _}, classify_fn) do
      raise ArgumentError, ":classify_fn is required in orchestration config"
    end

    classification = call_callable(classify_fn, [task_data])
    path = classification_path(classification)

    state =
      state
      |> increment_stat(:total)

    cond do
      path in [:fast_path, :routed] ->
        handle_routed_task(
          config,
          orchestration,
          state,
          task_data,
          classification,
          signal,
          router,
          emits,
          roles
        )

      true ->
        handle_dispatched_task(
          config,
          orchestration,
          state,
          task_data,
          classification,
          signal,
          router,
          roles
        )
    end
  end

  defp handle_routed_task(
         config,
         orchestration,
         state,
         task_data,
         classification,
         signal,
         router,
         emits,
         roles
       ) do
    fast_path_fn = Map.get(orchestration, :fast_path_fn)
    state = increment_stat(state, :routed)

    task_state =
      build_task_state(signal, classification, [])
      |> Map.put(:task_data, task_data)

    summary_topic = summary_topic(roles, emits)
    summary = build_summary(orchestration, [], task_state)
    publish_summary(router, config.id, summary, task_state.task_id, summary_topic)
    emit_summary_telemetry(config.id, summary)
    maybe_emit_signal(router, emits, config.id, summary)

    if fast_path_fn do
      call_callable(fast_path_fn, [signal, router])
    end

    {:ok, %{state: state}}
  end

  defp handle_dispatched_task(
         config,
         orchestration,
         state,
         task_data,
         classification,
         signal,
         router,
         roles
       ) do
    spawn_spec = Map.get(orchestration, :spawn_specialists)
    specialists = resolve_specialists(spawn_spec, task_data, classification)

    task_state =
      build_task_state(signal, classification, specialists)
      |> Map.put(:task_data, task_data)

    updated_state =
      state
      |> increment_stat(:dispatched)
      |> put_in([:tasks, task_state.task_id], task_state)

    if specialists == [] do
      complete_task(config, orchestration, updated_state, task_state.task_id, router, roles)
    else
      {:ok, %{state: updated_state}}
    end
  end

  defp handle_orchestrator_result(config, orchestration, state, signal, router, roles) do
    state = ensure_orchestrator_state(state)
    result = Map.new(signal.data)
    task_id = extract_task_id(result)

    case get_in(state, [:tasks, task_id]) do
      nil ->
        {:ok, %{state: state}}

      task_state ->
        negotiated_state =
          maybe_negotiate(Map.get(orchestration, :negotiate_fn), task_state, result)

        updated_state =
          state
          |> put_in([:tasks, task_id], update_task_state(negotiated_state, result))

        pending = get_in(updated_state, [:tasks, task_id, :pending])

        if pending == [] do
          complete_task(config, orchestration, updated_state, task_id, router, roles)
        else
          {:ok, %{state: updated_state}}
        end
    end
  end

  defp complete_task(config, orchestration, state, task_id, router, roles) do
    case get_in(state, [:tasks, task_id]) do
      nil ->
        {:ok, %{state: state}}

      task_state ->
        duration_ms = duration_ms(task_state.started_at)

        task_state =
          task_state
          |> Map.update(:metadata, %{}, fn metadata ->
            metadata
            |> Map.put(:duration_ms, duration_ms)
            |> Map.put(
              :specialists_resolved,
              Enum.uniq(task_state.metadata.specialists_resolved)
            )
          end)

        results = Enum.reverse(task_state.results)
        summary = build_summary(orchestration, results, task_state)
        summary_topic = summary_topic(roles, Map.get(config.signals, :emits, []))

        publish_summary(router, config.id, summary, task_id, summary_topic)
        emit_summary_telemetry(config.id, summary)
        maybe_emit_signal(router, config.signals.emits || [], config.id, summary)

        updated_state =
          state
          |> update_in([:tasks], &Map.delete(&1, task_id))
          |> increment_stat(:completed)

        {:ok, %{state: updated_state}}
    end
  end

  defp build_task_state(signal, classification, specialists) do
    task_id = extract_task_id(signal.data)

    %{
      task_id: task_id,
      review_id: task_id,
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

  defp extract_task_id(data) do
    Map.get(data, :task_id) ||
      Map.get(data, "task_id") ||
      Map.get(data, :review_id) ||
      Map.get(data, "review_id")
  end

  defp update_task_state(task_state, result) do
    agent = result_agent(result)

    task_state
    |> update_in([:results], &[result | &1])
    |> update_in([:pending], fn pending -> Enum.reject(pending, &(&1 == agent)) end)
    |> update_in([:metadata, :specialists_resolved], &[agent | &1])
  end

  defp ensure_orchestrator_state(state) do
    state
    |> Map.put_new(:tasks, %{})
    |> Map.put_new(:stats, %{total: 0, routed: 0, dispatched: 0, completed: 0, failed: 0})
  end

  defp increment_stat(state, key) do
    normalized_key = Map.get(%{fast_path: :routed, deep_review: :dispatched}, key, key)

    update_in(state, [:stats, normalized_key], fn
      nil -> 1
      value -> value + 1
    end)
  end

  defp classification_path(%{path: path}) when is_binary(path), do: String.to_atom(path)
  defp classification_path(%{path: path}) when is_atom(path), do: path
  defp classification_path(_), do: :dispatched

  defp initial_state(config) do
    case Map.get(config, :initial_state) do
      nil -> @orchestrator_defaults
      %{} = custom -> Map.merge(@orchestrator_defaults, custom)
      _ -> @orchestrator_defaults
    end
  end

  defp summary_topic(roles, emits) do
    cond do
      roles[:summary] -> roles.summary
      is_list(emits) and emits != [] -> hd(emits)
      true -> :review_summary
    end
  end

  defp resolve_specialists(nil, _task_data, _classification), do: []

  defp resolve_specialists(list, _task_data, _classification) when is_list(list) do
    Enum.map(list, &normalize_specialist_id/1)
  end

  defp resolve_specialists(callable, task_data, classification) do
    callable
    |> call_callable([task_data, classification])
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

  defp build_summary(orchestration, results, task_state) do
    aggregation_fn = Map.get(orchestration, :aggregation_fn)

    unless is_function(aggregation_fn) or match?({_, _, _}, aggregation_fn) do
      raise ArgumentError, ":aggregation_fn is required in orchestration config"
    end

    summary =
      call_callable(aggregation_fn, [results, task_state])
      |> ensure_summary_metadata(task_state)

    if is_map(summary) do
      summary
    else
      raise ArgumentError, ":aggregation_fn must return a map conforming to summary schema"
    end
  end

  defp ensure_summary_metadata(summary, task_state) when is_map(summary) do
    metadata =
      summary
      |> Map.get(:metadata, %{})
      |> Map.put_new(:decision_path, task_state.classification_path)

    Map.put(summary, :metadata, metadata)
  end

  defp ensure_summary_metadata(summary, _task_state), do: summary

  defp publish_summary(router, config_id, summary, task_id, topic) do
    topic = topic || :review_summary

    case SignalRouter.publish(
           router,
           topic,
           summary,
           source: "/synapse/agents/#{config_id}",
           subject: "synapse://agents/#{config_id}/task/#{task_id}"
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish task summary",
          router: router,
          config: config_id,
          topic: topic,
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

  defp maybe_negotiate(nil, task_state, _result), do: task_state

  defp maybe_negotiate(callback, task_state, result) do
    case call_callable(callback, [result, task_state]) do
      {:ok, new_state} when is_map(new_state) -> new_state
      new_state when is_map(new_state) -> new_state
      _ -> task_state
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

    event_metadata =
      %{
        config_id: config_id,
        task_id: summary_task_id(summary),
        status: Map.get(summary, :status, :unknown) || :unknown,
        severity: Map.get(summary, :severity, :none) || :none,
        decision_path: metadata[:decision_path] || metadata["decision_path"],
        specialists: specialists,
        escalations: Map.get(summary, :escalations, []) || [],
        negotiations: negotiations
      }
      |> maybe_put_review_id(summary)

    :telemetry.execute(
      [:synapse, :workflow, :orchestrator, :summary],
      measurements,
      event_metadata
    )
  rescue
    error ->
      Logger.warning("Failed to emit orchestrator summary telemetry",
        config_id: config_id,
        summary: Map.take(summary, [:task_id, :review_id, :status, :severity]),
        reason: Exception.message(error)
      )
  end

  defp summary_task_id(summary) do
    Map.get(summary, :task_id) ||
      Map.get(summary, "task_id") ||
      Map.get(summary, :review_id) ||
      Map.get(summary, "review_id")
  end

  defp maybe_put_review_id(map, summary) do
    review_id = Map.get(summary, :review_id) || Map.get(summary, "review_id")

    if is_nil(review_id) do
      map
    else
      Map.put(map, :review_id, review_id)
    end
  end

  defp log_crash(error, stacktrace) do
    Logger.error("""
    RunConfig crashed
    #{Exception.format(:error, error, stacktrace)}
    """)
  end
end
