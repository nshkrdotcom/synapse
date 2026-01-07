defmodule ReviewBot.Workflows.MultiProviderReview do
  @moduledoc """
  Synapse workflow for multi-provider code review with persistence and PubSub.

  This workflow:
  1. Executes code review with multiple providers in parallel
  2. Each step broadcasts results via PubSub for real-time UI updates
  3. Aggregates results from all providers
  4. Persists workflow state to Postgres via Synapse persistence
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias Synapse.Workflow.Persistence.Postgres
  alias ReviewBot.Actions.{ReviewCode, AggregateReviews}
  alias ReviewBot.Reviews
  alias ReviewBot.Reviews.Review

  @default_providers [:claude, :codex, :gemini]

  @doc """
  Run a multi-provider code review workflow.

  ## Options
  - `:providers` - List of provider atoms (default: [:claude, :codex, :gemini])
  """
  def run(%Review{} = review, opts \\ []) do
    providers = Keyword.get(opts, :providers, @default_providers)

    # Update review status to in_progress
    Reviews.update_review_status(review, :in_progress)

    spec = build_spec(review, providers)

    # Execute with Synapse persistence
    case Engine.execute(spec,
           input: %{code: review.code, language: review.language},
           context: %{request_id: review.workflow_id, review_id: review.id},
           persistence: {Postgres, repo: ReviewBot.Repo}
         ) do
      {:ok, %{outputs: outputs}} ->
        # Final update is handled by AggregateReviews action
        {:ok, outputs}

      {:error, failure} ->
        # Update review to failed status
        Reviews.update_review_status(review, :failed)

        Phoenix.PubSub.broadcast(
          ReviewBot.PubSub,
          "review:#{review.id}",
          {:review_failed, failure}
        )

        {:error, failure}
    end
  end

  defp build_spec(review, providers) do
    # Build dynamic steps for each provider
    provider_steps =
      Enum.map(providers, fn provider ->
        [
          id: :"#{provider}_review",
          action: ReviewCode,
          params: %{
            code: review.code,
            language: review.language,
            provider: provider
          },
          label: "Review with #{provider}",
          on_error: :continue,
          retry: [max_attempts: 2, backoff: 500],
          metadata: %{provider: provider}
        ]
      end)

    # Aggregation step depends on all provider steps
    aggregate_step = [
      id: :aggregate,
      action: AggregateReviews,
      label: "Aggregate reviews",
      requires: Enum.map(providers, &:"#{&1}_review"),
      params: fn env ->
        results =
          Enum.map(providers, fn provider ->
            {provider, Map.get(env.results, :"#{provider}_review")}
          end)

        %{results: results, review_id: review.id}
      end
    ]

    Spec.new(
      name: :multi_provider_review,
      description: "Multi-provider code review for review ##{review.id}",
      metadata: %{
        review_id: review.id,
        workflow_id: review.workflow_id,
        providers: providers,
        language: review.language
      },
      steps: provider_steps ++ [aggregate_step],
      outputs: [
        [key: :combined, from: :aggregate, path: [:combined]],
        [key: :individual, from: :aggregate, path: [:individual]],
        [key: :summary, from: :aggregate, path: [:summary]]
      ]
    )
  end

  @doc """
  Run review asynchronously in a separate process.
  Returns the review immediately and broadcasts updates via PubSub.
  """
  def run_async(%Review{} = review, opts \\ []) do
    Task.start(fn ->
      run(review, opts)
    end)

    {:ok, review}
  end
end
