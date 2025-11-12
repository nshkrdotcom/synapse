defmodule Synapse.Workflows.ReviewSummaryWorkflow do
  @moduledoc """
  Executes `Synapse.Actions.Review.GenerateSummary` via the workflow engine so
  summary generation benefits from persistence and telemetry.
  """

  alias Synapse.Actions.Review.GenerateSummary
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step
  alias Synapse.Workflows.ChainHelpers

  @type input :: %{
          required(:review_id) => String.t(),
          required(:findings) => [map()],
          optional(:metadata) => map()
        }

  @doc """
  Generates a review summary from aggregated specialist findings.
  """
  @spec generate(map(), keyword()) :: {:ok, map()} | {:error, Jido.Error.t()}
  def generate(input, opts \\ [])

  def generate(input, opts) when is_map(input) do
    normalized = normalize_input(input)

    context =
      opts
      |> Keyword.get(:context)
      |> ensure_context(normalized.review_id)

    engine_opts =
      opts
      |> Keyword.put(:input, normalized)
      |> Keyword.put(:context, context)

    case Engine.execute(summary_spec(), engine_opts) do
      {:ok, exec} ->
        {:ok, exec.outputs.summary}

      {:error, failure} ->
        {:error, failure.error}
    end
  end

  def generate(_invalid, _opts) do
    {:error,
     Jido.Error.validation_error(
       "summary input must be a map",
       %{required: [:review_id, :findings]}
     )}
  end

  defp normalize_input(params) do
    %{
      review_id: Map.get(params, :review_id, Map.get(params, "review_id")),
      findings: Map.get(params, :findings, Map.get(params, "findings", [])),
      metadata: Map.get(params, :metadata, Map.get(params, "metadata", %{}))
    }
  end

  defp ensure_context(nil, review_id) do
    %{
      request_id: build_request_id(review_id),
      review_id: review_id
    }
  end

  defp ensure_context(context, review_id) do
    context
    |> Map.put_new(:request_id, build_request_id(review_id))
    |> Map.put_new(:review_id, review_id)
  end

  defp build_request_id(nil), do: ChainHelpers.generate_request_id()
  defp build_request_id(review_id), do: "#{review_id}-summary"

  defp summary_spec do
    Spec.new(
      name: :review_summary_workflow,
      description: "Generates review.summary payloads",
      metadata: %{version: 1},
      steps: [
        Step.new(
          id: :generate_summary,
          action: GenerateSummary,
          label: "Generate Summary",
          description: "Synthesizes findings and metadata into a final summary",
          params: fn env ->
            %{
              review_id: Map.fetch!(env.input, :review_id),
              findings: Map.get(env.input, :findings, []),
              metadata: Map.get(env.input, :metadata, %{})
            }
          end
        )
      ],
      outputs: [
        Spec.output(:summary, from: :generate_summary)
      ]
    )
  end
end
