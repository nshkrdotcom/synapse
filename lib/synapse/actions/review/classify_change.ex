defmodule Synapse.Actions.Review.ClassifyChange do
  @moduledoc """
  Classifies a code review request to determine the appropriate review path.

  Returns either `:fast_path` for small, low-risk changes or `:deep_review`
  for changes requiring thorough specialist analysis.

  Classification criteria:
  - Files changed > 50: deep review
  - Security or performance labels: deep review
  - High risk factor (>= 0.5): deep review
  - Hotfix intent: fast path (override)
  - Default: fast path
  """

  use Jido.Action,
    name: "classify_change",
    description: "Determines review path based on change characteristics",
    schema: [
      files_changed: [
        type: :non_neg_integer,
        required: true,
        doc: "Number of files modified in the change"
      ],
      labels: [
        type: {:list, :string},
        required: true,
        doc: "Labels or tags associated with the change"
      ],
      intent: [
        type: :string,
        required: true,
        doc: "Intent of the change (e.g., 'feature', 'hotfix', 'refactor')"
      ],
      risk_factor: [
        type: :float,
        default: 0.0,
        doc: "Risk score from 0.0 (low) to 1.0 (high)"
      ]
    ]

  require Logger

  @impl true
  def on_before_validate_params(params) do
    # Ensure risk_factor has default if not provided
    params_with_defaults = Map.put_new(params, :risk_factor, 0.0)
    {:ok, params_with_defaults}
  end

  @impl true
  def run(params, context) do
    review_id = Map.get(context, :review_id)

    classification = classify(params)
    rationale = build_rationale(params, classification)

    Logger.debug("Change classified",
      review_id: review_id,
      path: classification,
      rationale: rationale
    )

    result = %{
      path: classification,
      rationale: rationale
    }

    result =
      if review_id do
        Map.put(result, :review_id, review_id)
      else
        result
      end

    {:ok, result}
  end

  # Classification logic following architecture.md decision rules
  defp classify(params) do
    cond do
      # Hotfix intent overrides other rules for fast path
      params.intent == "hotfix" ->
        :fast_path

      # Large changes require deep review
      params.files_changed > 50 ->
        :deep_review

      # Security or performance labels trigger deep review
      has_risk_label?(params.labels) ->
        :deep_review

      # High risk factor triggers deep review
      params.risk_factor >= 0.5 ->
        :deep_review

      # Default to fast path for small, unlabelled changes
      true ->
        :fast_path
    end
  end

  defp has_risk_label?(labels) do
    risk_labels = ["security", "performance"]
    Enum.any?(labels, &(&1 in risk_labels))
  end

  defp build_rationale(params, :fast_path) do
    cond do
      params.intent == "hotfix" ->
        "Fast path: hotfix intent allows expedited review"

      params.files_changed <= 10 ->
        "Fast path: small change (#{params.files_changed} files), no risk labels"

      true ->
        "Fast path: moderate change (#{params.files_changed} files) with low risk"
    end
  end

  defp build_rationale(params, :deep_review) do
    reasons = []

    reasons =
      if params.files_changed > 50 do
        ["#{params.files_changed} files changed (threshold: 50)" | reasons]
      else
        reasons
      end

    reasons =
      if has_risk_label?(params.labels) do
        ["security/performance labels detected" | reasons]
      else
        reasons
      end

    reasons =
      if params.risk_factor >= 0.5 do
        ["high risk factor (#{params.risk_factor})" | reasons]
      else
        reasons
      end

    "Deep review required: " <> Enum.join(reasons, ", ")
  end
end
