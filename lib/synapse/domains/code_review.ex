defmodule Synapse.Domains.CodeReview do
  @moduledoc """
  Code review domain for Synapse.

  This module registers code-review-specific signal topics and provides
  pre-built actions for security and performance analysis of code changes.

  ## Usage

      # In application.ex or runtime config
      Synapse.Domains.CodeReview.register()

  Or in config:

      config :synapse, :domains, [Synapse.Domains.CodeReview]

  ## Signals

  This domain registers the following signal topics:

  - `:review_request` - Incoming code review requests
  - `:review_result` - Results from specialist agents
  - `:review_summary` - Aggregated review summaries
  - `:specialist_ready` - Specialist availability notifications

  ## Actions

  Available actions for building review workflows:

  ### Review Actions
  - `Synapse.Domains.CodeReview.Actions.ClassifyChange`
  - `Synapse.Domains.CodeReview.Actions.GenerateSummary`
  - `Synapse.Domains.CodeReview.Actions.DecideEscalation`

  ### Security Actions
  - `Synapse.Domains.CodeReview.Actions.CheckSQLInjection`
  - `Synapse.Domains.CodeReview.Actions.CheckXSS`
  - `Synapse.Domains.CodeReview.Actions.CheckAuthIssues`

  ### Performance Actions
  - `Synapse.Domains.CodeReview.Actions.CheckComplexity`
  - `Synapse.Domains.CodeReview.Actions.CheckMemoryUsage`
  - `Synapse.Domains.CodeReview.Actions.ProfileHotPath`
  """

  alias Synapse.Signal.Registry

  @doc """
  Registers all code review signal topics with the Signal Registry.

  Call this function during application startup to enable code review signals.
  """
  @spec register() :: :ok | {:error, term()}
  def register, do: register(Registry)

  @doc """
  Registers all code review signal topics with the provided registry.
  """
  @spec register(atom() | pid()) :: :ok | {:error, term()}
  def register(registry) do
    with :ok <- register_review_request(registry),
         :ok <- register_review_result(registry),
         :ok <- register_review_summary(registry),
         :ok <- register_specialist_ready(registry) do
      :ok
    end
  end

  @doc """
  Returns the list of signal topics registered by this domain.
  """
  @spec topics() :: [atom()]
  def topics do
    [:review_request, :review_result, :review_summary, :specialist_ready]
  end

  @doc """
  Returns all action modules provided by this domain.
  """
  @spec actions() :: [module()]
  def actions do
    [
      __MODULE__.Actions.ClassifyChange,
      __MODULE__.Actions.GenerateSummary,
      __MODULE__.Actions.DecideEscalation,
      __MODULE__.Actions.CheckSQLInjection,
      __MODULE__.Actions.CheckXSS,
      __MODULE__.Actions.CheckAuthIssues,
      __MODULE__.Actions.CheckComplexity,
      __MODULE__.Actions.CheckMemoryUsage,
      __MODULE__.Actions.ProfileHotPath
    ]
  end

  defp register_review_request(registry) do
    register_topic(registry, :review_request,
      type: "review.request",
      schema: [
        review_id: [type: :string, required: true, doc: "Unique identifier for the review"],
        diff: [type: :string, default: "", doc: "Unified diff or snippet under review"],
        metadata: [
          type: :map,
          default: %{},
          doc: "Arbitrary metadata describing the review target"
        ],
        files_changed: [type: :integer, default: 0, doc: "Count of files changed in the review"],
        labels: [
          type: {:list, :string},
          default: [],
          doc: "Labels or tags attached to the review"
        ],
        intent: [type: :string, default: "feature", doc: "Intent label used for routing"],
        risk_factor: [
          type: :float,
          default: 0.0,
          doc: "Risk multiplier used during classification"
        ],
        files: [
          type: {:list, :string},
          default: [],
          doc: "List of files referenced by the review"
        ],
        language: [type: :string, default: "elixir", doc: "Primary language hint for the review"]
      ]
    )
  end

  defp register_review_result(registry) do
    register_topic(registry, :review_result,
      type: "review.result",
      schema: [
        review_id: [
          type: :string,
          required: true,
          doc: "Review identifier the findings belong to"
        ],
        agent: [type: :string, required: true, doc: "Logical specialist identifier"],
        confidence: [type: :float, default: 0.0, doc: "Confidence score for the findings"],
        findings: [
          type: {:list, :map},
          default: [],
          doc: "List of findings detected by the specialist"
        ],
        should_escalate: [
          type: :boolean,
          default: false,
          doc: "Signals whether human escalation is recommended"
        ],
        metadata: [
          type: :map,
          default: %{},
          doc: "Additional execution metadata emitted by the specialist"
        ]
      ]
    )
  end

  defp register_review_summary(registry) do
    register_topic(registry, :review_summary,
      type: "review.summary",
      schema: [
        review_id: [type: :string, required: true, doc: "Review identifier"],
        status: [type: :atom, default: :complete, doc: "Overall status for the review workflow"],
        severity: [type: :atom, default: :none, doc: "Max severity across all findings"],
        findings: [type: {:list, :map}, default: [], doc: "Combined findings ordered by severity"],
        recommendations: [
          type: {:list, :any},
          default: [],
          doc: "Recommended actions for follow-up"
        ],
        escalations: [
          type: {:list, :string},
          default: [],
          doc: "Reason(s) for triggering escalation"
        ],
        metadata: [
          type: :map,
          default: %{},
          doc: "Coordinator metadata (decision path, runtime stats, etc.)"
        ]
      ]
    )
  end

  defp register_specialist_ready(registry) do
    register_topic(registry, :specialist_ready,
      type: "review.specialist_ready",
      schema: [
        specialist_id: [type: :string, required: true, doc: "Specialist identifier"],
        capabilities: [
          type: {:list, :string},
          default: [],
          doc: "List of capabilities this specialist provides"
        ]
      ]
    )
  end

  defp register_topic(registry, topic, opts) do
    case Registry.register_topic(registry, topic, opts) do
      :ok -> :ok
      {:error, :already_registered} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
