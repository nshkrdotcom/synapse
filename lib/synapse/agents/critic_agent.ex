defmodule Synapse.Agents.CriticAgent do
  @moduledoc """
  Agent that specializes in reviewing code and maintaining review history.
  Tracks patterns and learns from corrections over time.
  """

  use Jido.Agent,
    name: "critic_agent",
    description: "Reviews code and learns from feedback",
    actions: [
      Synapse.Actions.CriticReview
    ],
    schema: [
      review_count: [type: :integer, default: 0, doc: "Number of reviews performed"],
      review_history: [type: {:list, :map}, default: [], doc: "History of reviews"],
      learned_patterns: [
        type: {:list, :map},
        default: [],
        doc: "Patterns learned from feedback"
      ],
      decision_fossils: [
        type: {:list, :map},
        default: [],
        doc: "Short summaries of notable reviews for planner context"
      ],
      scar_tissue: [
        type: {:list, :map},
        default: [],
        doc: "Historical record of failed attempts and mitigations"
      ]
    ]

  require Logger

  @impl true
  def on_after_run(agent, result, _directives) do
    Logger.debug("CriticAgent: Review completed")

    # Extract result from result map if available, otherwise use defaults
    result = result || %{confidence: 0, issues: [], should_escalate: false}
    now = DateTime.utc_now()

    history_entry = %{
      timestamp: now,
      confidence: Map.get(result, :confidence, 0),
      issues_found: length(Map.get(result, :issues, [])),
      escalated: Map.get(result, :should_escalate, false)
    }

    fossil_entry = %{
      timestamp: now,
      confidence: Map.get(result, :confidence, 0),
      escalated: Map.get(result, :should_escalate, false),
      summary: build_summary(result)
    }

    set(
      agent,
      %{
        review_count: agent.state.review_count + 1,
        review_history: Enum.take([history_entry | agent.state.review_history], 100),
        decision_fossils: Enum.take([fossil_entry | agent.state.decision_fossils], 50)
      }
    )
  end

  @doc """
  Learns from a correction/feedback.
  This would be called after HITL provides feedback.
  """
  def learn_from_correction(agent, correction) do
    # Store the correction as a learned pattern
    pattern_key = generate_pattern_key(correction)

    updated_patterns =
      case Enum.find(agent.state.learned_patterns, &(&1.pattern == pattern_key)) do
        nil ->
          [
            %{pattern: pattern_key, count: 1, examples: [correction]}
            | agent.state.learned_patterns
          ]

        existing ->
          updated_entry = %{
            existing
            | count: existing.count + 1,
              examples: Enum.take([correction | existing.examples], 10)
          }

          [
            updated_entry
            | Enum.reject(agent.state.learned_patterns, &(&1.pattern == pattern_key))
          ]
      end

    set(agent, %{learned_patterns: updated_patterns})
  end

  @doc """
  Records a failed attempt (scar tissue) so future runs can avoid repeating the issue.
  """
  def record_failure(agent, failure_details) when is_map(failure_details) do
    entry =
      failure_details
      |> Map.put_new(:timestamp, DateTime.utc_now())

    set(
      agent,
      %{
        scar_tissue: Enum.take([entry | agent.state.scar_tissue], 50)
      }
    )
  end

  defp generate_pattern_key(correction) do
    # Simple key generation - in production this would be more sophisticated
    "pattern_#{:erlang.phash2(correction.context)}"
  end

  defp build_summary(result) do
    issues =
      result
      |> Map.get(:issues, [])
      |> Enum.join("; ")
      |> String.slice(0, 140)

    confidence = Map.get(result, :confidence, 0)

    if issues == "" do
      "Confidence #{Float.round(confidence * 100, 1)}% – no issues detected."
    else
      "Confidence #{Float.round(confidence * 100, 1)}% – issues: #{issues}"
    end
  end
end
