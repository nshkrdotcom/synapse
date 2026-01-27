defmodule Synapse.CoordinationTelemetry do
  @moduledoc """
  Telemetry event emission for Synapse coordination lifecycle.

  Emits structured telemetry events at each stage of multi-agent
  coordination for monitoring, alerting, and cost tracking.

  ## Events

    * `[:synapse, :coordination, :started]` - Coordination initiated
    * `[:synapse, :agent, :invoked]` - Individual agent invoked
    * `[:synapse, :agent, :completed]` - Individual agent completed
    * `[:synapse, :iteration, :completed]` - Coordination iteration completed
    * `[:synapse, :consensus, :checked]` - Consensus score evaluated
    * `[:synapse, :coordination, :completed]` - Coordination finished
    * `[:synapse, :escalation, :triggered]` - Escalation to human review
  """

  @doc """
  Emit coordination started event.
  """
  @spec emit_coordination_started(map()) :: :ok
  def emit_coordination_started(request) do
    :telemetry.execute(
      [:synapse, :coordination, :started],
      %{system_time: System.system_time()},
      %{
        run_id: Map.get(request, :run_id),
        step_id: Map.get(request, :step_id),
        coordinator: get_in(request, [:synapse_spec, :coordinator]),
        agents: get_in(request, [:synapse_spec, :agents]) || [],
        max_iterations: get_in(request, [:synapse_spec, :max_iterations])
      }
    )

    :ok
  end

  @doc """
  Emit agent invoked event.
  """
  @spec emit_agent_invoked(String.t(), non_neg_integer(), atom(), atom()) :: :ok
  def emit_agent_invoked(run_id, iteration, agent_id, action) do
    :telemetry.execute(
      [:synapse, :agent, :invoked],
      %{system_time: System.system_time()},
      %{
        run_id: run_id,
        iteration: iteration,
        agent_id: agent_id,
        action: action
      }
    )

    :ok
  end

  @doc """
  Emit agent completed event.
  """
  @spec emit_agent_completed(
          String.t(),
          non_neg_integer(),
          atom(),
          atom(),
          map()
        ) :: :ok
  def emit_agent_completed(run_id, iteration, agent_id, status, measurements) do
    :telemetry.execute(
      [:synapse, :agent, :completed],
      %{
        duration_ms: Map.get(measurements, :duration_ms, 0),
        input_tokens: Map.get(measurements, :input_tokens, 0),
        output_tokens: Map.get(measurements, :output_tokens, 0)
      },
      %{
        run_id: run_id,
        iteration: iteration,
        agent_id: agent_id,
        status: status
      }
    )

    :ok
  end

  @doc """
  Emit iteration completed event.
  """
  @spec emit_iteration_completed(
          String.t(),
          non_neg_integer(),
          [atom()],
          float() | nil,
          non_neg_integer()
        ) :: :ok
  def emit_iteration_completed(run_id, iteration, agents_completed, consensus_score, duration_ms) do
    :telemetry.execute(
      [:synapse, :iteration, :completed],
      %{
        duration_ms: duration_ms,
        iteration: iteration
      },
      %{
        run_id: run_id,
        agents_completed: agents_completed,
        consensus_score: consensus_score
      }
    )

    :ok
  end

  @doc """
  Emit consensus checked event.
  """
  @spec emit_consensus_checked(String.t(), non_neg_integer(), float(), float(), boolean()) :: :ok
  def emit_consensus_checked(run_id, iteration, score, threshold, reached) do
    :telemetry.execute(
      [:synapse, :consensus, :checked],
      %{
        consensus_score: score,
        threshold: threshold
      },
      %{
        run_id: run_id,
        iteration: iteration,
        reached: reached
      }
    )

    :ok
  end

  @doc """
  Emit coordination completed event.
  """
  @spec emit_coordination_completed(String.t(), atom(), map()) :: :ok
  def emit_coordination_completed(run_id, status, measurements) do
    :telemetry.execute(
      [:synapse, :coordination, :completed],
      %{
        total_duration_ms: Map.get(measurements, :total_duration_ms, 0),
        total_iterations: Map.get(measurements, :total_iterations, 0),
        total_tokens: Map.get(measurements, :total_tokens, 0),
        total_cost_usd: Map.get(measurements, :total_cost_usd, 0.0)
      },
      %{
        run_id: run_id,
        status: status,
        final_consensus_score: Map.get(measurements, :final_consensus_score)
      }
    )

    :ok
  end

  @doc """
  Emit escalation triggered event.
  """
  @spec emit_escalation_triggered(String.t(), atom(), atom(), map()) :: :ok
  def emit_escalation_triggered(run_id, reason, escalation_type, agent_positions) do
    :telemetry.execute(
      [:synapse, :escalation, :triggered],
      %{system_time: System.system_time()},
      %{
        run_id: run_id,
        reason: reason,
        escalation_type: escalation_type,
        agent_positions: agent_positions
      }
    )

    :ok
  end
end
