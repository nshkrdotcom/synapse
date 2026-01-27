defmodule Synapse do
  @moduledoc """
  Synapse is a headless, declarative multi-agent orchestration framework.

  Provides the `coordinate/3` entry point for FlowStone to delegate agentic
  steps to Synapse for LLM-driven reasoning, multi-agent consensus, and
  human escalation.

  ## Usage

      spec = %{
        coordinator: :code_review_coordinator,
        agents: [:reviewer_agent, :security_agent],
        max_iterations: 5,
        consensus_threshold: 0.8,
        escalation_policy: :on_no_consensus
      }

      inputs = %{code_diff: diff, requirements: reqs}

      context = %{
        agent_runner: runner,
        artifact_store: store,
        timeout_remaining_ms: 280_000
      }

      case Synapse.coordinate(spec, inputs, context) do
        {:ok, result} -> # Consensus reached
        {:escalate, result} -> # Human decision needed
        {:timeout, result} -> # Budget exhausted
        {:error, reason} -> # Coordination failed
      end
  """

  alias Synapse.{
    Consensus,
    CoordinationState,
    CoordinationTelemetry,
    CoordinatorSpec,
    DelegationRequest,
    DelegationResult,
    Escalation,
    TimeoutManager
  }

  @type synapse_spec :: DelegationRequest.synapse_spec()
  @type delegation_context :: DelegationRequest.delegation_context()

  @doc """
  Coordinate multi-agent execution for an agentic FlowStone step.

  ## Parameters

    * `spec` - Agent coordination configuration (synapse_spec)
    * `inputs` - Data from previous pipeline steps
    * `context` - FlowStone resource bindings and metadata

  ## Returns

    * `{:ok, DelegationResult.t()}` - Coordination succeeded with consensus
    * `{:escalate, DelegationResult.t()}` - Human decision required
    * `{:timeout, DelegationResult.t()}` - Time budget exhausted
    * `{:error, reason}` - Coordination failed
  """
  @spec coordinate(synapse_spec(), map(), delegation_context()) ::
          {:ok, DelegationResult.t()}
          | {:escalate, DelegationResult.t()}
          | {:timeout, DelegationResult.t()}
          | {:error, term()}
  def coordinate(spec, inputs, context) do
    with {:ok, request} <- build_request(spec, inputs, context),
         {:ok, coordinator_spec} <- build_coordinator_spec(spec),
         {:ok, state} <- init_coordination(request, coordinator_spec) do
      CoordinationTelemetry.emit_coordination_started(request)
      run_coordination_loop(state, request, inputs, context)
    end
  end

  # Build and validate the delegation request
  defp build_request(spec, inputs, context) do
    run_id = Map.get(context, :run_id, generate_id())
    step_id = Map.get(context, :step_id, "unknown")
    timeout_ms = Map.get(context, :timeout_remaining_ms, 300_000)

    attrs = %{
      run_id: run_id,
      step_id: step_id,
      synapse_spec: spec,
      inputs: inputs,
      context: context,
      timeout_ms: timeout_ms
    }

    case DelegationRequest.validate(attrs) do
      {:ok, _validated} -> {:ok, attrs}
      {:error, _reason} -> {:error, :invalid_spec}
    end
  end

  # Build coordinator spec from synapse_spec
  defp build_coordinator_spec(spec) do
    coordinator_attrs = %{
      id: Map.get(spec, :coordinator, :default_coordinator),
      strategy: Map.get(spec, :strategy, :parallel),
      consensus_algorithm: Map.get(spec, :consensus_algorithm, :weighted_vote),
      weights: Map.get(spec, :weights, %{}),
      termination_conditions:
        build_termination_conditions(
          Map.get(spec, :consensus_threshold, 0.8),
          Map.get(spec, :max_iterations, 5),
          Map.get(spec, :timeout_ms)
        )
    }

    case CoordinatorSpec.validate(coordinator_attrs) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, {:invalid_coordinator_spec, reason}}
    end
  end

  defp build_termination_conditions(threshold, max_iterations, timeout_ms) do
    conditions = [
      {:consensus_reached, threshold: threshold},
      {:max_iterations, count: max_iterations}
    ]

    if timeout_ms do
      conditions ++ [{:timeout, ms: timeout_ms}]
    else
      conditions
    end
  end

  # Initialize coordination state
  defp init_coordination(request, coordinator_spec) do
    timeout_ms = Map.get(request, :timeout_ms, 300_000)
    request_id = Map.get(request, :run_id, generate_id())
    state = CoordinationState.new(request_id, coordinator_spec, timeout_ms)
    {:ok, state}
  end

  # Main coordination loop
  defp run_coordination_loop(state, request, inputs, context) do
    max_iterations = get_in(request, [:synapse_spec, :max_iterations]) || 5
    threshold = get_in(request, [:synapse_spec, :consensus_threshold]) || 0.8
    agents = get_in(request, [:synapse_spec, :agents]) || []
    algorithm = state.coordinator_spec.consensus_algorithm
    weights = state.coordinator_spec.weights
    run_id = Map.get(request, :run_id, "unknown")
    start_time = System.monotonic_time(:millisecond)

    do_coordination_loop(
      state,
      request,
      inputs,
      context,
      max_iterations,
      threshold,
      agents,
      algorithm,
      weights,
      run_id,
      start_time
    )
  end

  defp do_coordination_loop(
         state,
         request,
         inputs,
         context,
         max_iterations,
         threshold,
         agents,
         algorithm,
         weights,
         run_id,
         start_time
       ) do
    # Check timeout before each iteration
    elapsed = System.monotonic_time(:millisecond) - start_time
    timeout_state = %{state | elapsed_ms: elapsed}

    case TimeoutManager.should_terminate?(timeout_state) do
      {:timeout, partial} ->
        build_timeout_response(partial, run_id, elapsed)

      :continue ->
        iteration = state.iteration + 1

        if iteration > max_iterations do
          # Max iterations reached - escalate or fail
          handle_max_iterations_reached(state, request, run_id, elapsed)
        else
          # Run agents for this iteration
          iter_start = System.monotonic_time(:millisecond)
          agent_states = run_agents(agents, inputs, context, run_id, iteration)

          # Calculate consensus
          score = Consensus.calculate_consensus(agent_states, algorithm, weights)
          reached = Consensus.consensus_reached?(score, threshold)

          iter_duration = System.monotonic_time(:millisecond) - iter_start
          completed_agents = Map.keys(agent_states)

          CoordinationTelemetry.emit_iteration_completed(
            run_id,
            iteration,
            completed_agents,
            score,
            iter_duration
          )

          CoordinationTelemetry.emit_consensus_checked(
            run_id,
            iteration,
            score,
            threshold,
            reached
          )

          updated_state = %{
            state
            | iteration: iteration,
              agent_states: agent_states,
              consensus_score: score,
              elapsed_ms: System.monotonic_time(:millisecond) - start_time,
              timeout_remaining_ms:
                state.timeout_remaining_ms -
                  (System.monotonic_time(:millisecond) - start_time),
              last_updated_at: DateTime.utc_now()
          }

          if reached do
            build_success_response(updated_state, agent_states, run_id)
          else
            do_coordination_loop(
              updated_state,
              request,
              inputs,
              context,
              max_iterations,
              threshold,
              agents,
              algorithm,
              weights,
              run_id,
              start_time
            )
          end
        end
    end
  end

  # Run all agents for a single iteration
  defp run_agents(agents, inputs, context, run_id, iteration) do
    test_mode = Map.get(context, :test_mode, false)
    mock_responses = Map.get(context, :mock_responses, %{})

    agents
    |> Enum.map(fn agent_id ->
      CoordinationTelemetry.emit_agent_invoked(run_id, iteration, agent_id, :execute)

      agent_start = System.monotonic_time(:millisecond)

      result =
        if test_mode and Map.has_key?(mock_responses, agent_id) do
          mock_fn = Map.get(mock_responses, agent_id)
          mock_fn.(inputs)
        else
          # In production, delegate to actual agent execution
          execute_agent(agent_id, inputs, context)
        end

      duration = System.monotonic_time(:millisecond) - agent_start

      case result do
        {:ok, output} ->
          CoordinationTelemetry.emit_agent_completed(run_id, iteration, agent_id, :ok, %{
            duration_ms: duration
          })

          score = Map.get(output, :score, 1.0)
          {agent_id, %{status: :complete, output: output, score: score}}

        {:error, reason} ->
          CoordinationTelemetry.emit_agent_completed(run_id, iteration, agent_id, :error, %{
            duration_ms: duration
          })

          {agent_id, %{status: :error, output: nil, score: 0.0, error: reason}}
      end
    end)
    |> Map.new()
  end

  # Execute an agent (production path)
  defp execute_agent(_agent_id, _inputs, _context) do
    # Default implementation for agents not in test mode
    # In production, this would look up the agent and invoke it
    {:ok, %{position: :approve, score: 1.0}}
  end

  # Build success response
  defp build_success_response(state, agent_states, run_id) do
    outputs =
      agent_states
      |> Enum.into(%{}, fn {agent_id, agent_state} ->
        {agent_id, Map.get(agent_state, :output)}
      end)

    total_elapsed = state.elapsed_ms

    CoordinationTelemetry.emit_coordination_completed(run_id, :success, %{
      total_duration_ms: total_elapsed,
      total_iterations: state.iteration,
      total_tokens: 0,
      total_cost_usd: 0.0,
      final_consensus_score: state.consensus_score
    })

    result = %DelegationResult{
      status: :success,
      outputs: outputs,
      telemetry: %{
        iterations: state.iteration,
        total_tokens: 0,
        total_cost_usd: Decimal.new("0"),
        agents_invoked: Map.keys(agent_states),
        consensus_score: state.consensus_score
      }
    }

    {:ok, result}
  end

  # Handle max iterations reached without consensus
  defp handle_max_iterations_reached(state, request, run_id, elapsed) do
    _escalation_policy =
      get_in(request, [:synapse_spec, :escalation_policy]) || :on_no_consensus

    escalation_request =
      Escalation.build_escalation_request(
        %{
          agent_states: state.agent_states,
          consensus_score: state.consensus_score,
          iteration: state.iteration,
          request: request
        },
        :no_consensus
      )

    CoordinationTelemetry.emit_escalation_triggered(
      run_id,
      :no_consensus,
      escalation_request.type,
      escalation_request.agent_positions
    )

    CoordinationTelemetry.emit_coordination_completed(run_id, :escalate, %{
      total_duration_ms: elapsed,
      total_iterations: state.iteration,
      total_tokens: 0,
      total_cost_usd: 0.0,
      final_consensus_score: state.consensus_score
    })

    result = %DelegationResult{
      status: :escalate,
      reason: :no_consensus,
      escalation_request: escalation_request,
      partial_outputs: extract_partial_outputs(state.agent_states),
      telemetry: %{
        iterations: state.iteration,
        total_tokens: 0,
        total_cost_usd: Decimal.new("0"),
        agents_invoked: Map.keys(state.agent_states),
        consensus_score: state.consensus_score
      }
    }

    {:escalate, result}
  end

  # Build timeout response
  defp build_timeout_response(partial, run_id, elapsed) do
    CoordinationTelemetry.emit_coordination_completed(run_id, :timeout, %{
      total_duration_ms: elapsed,
      total_iterations: Map.get(partial, :iteration, 0),
      total_tokens: 0,
      total_cost_usd: 0.0,
      final_consensus_score: Map.get(partial, :consensus_score)
    })

    result = %DelegationResult{
      status: :timeout,
      reason: :consensus_timeout,
      partial_outputs: extract_partial_outputs(Map.get(partial, :agent_states, %{})),
      telemetry: %{
        iterations: Map.get(partial, :iteration, 0),
        total_tokens: 0,
        total_cost_usd: Decimal.new("0"),
        agents_invoked: Map.keys(Map.get(partial, :agent_states, %{})),
        consensus_score: Map.get(partial, :consensus_score)
      }
    }

    {:timeout, result}
  end

  defp extract_partial_outputs(agent_states) do
    agent_states
    |> Enum.into(%{}, fn {agent_id, state} ->
      {agent_id, Map.get(state, :output)}
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
