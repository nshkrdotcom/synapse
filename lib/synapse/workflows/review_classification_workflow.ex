defmodule Synapse.Workflows.ReviewClassificationWorkflow do
  @moduledoc """
  Runs `Synapse.Actions.Review.ClassifyChange` via the workflow engine so
  classification gains audit trails, retries, and persistence.
  """

  alias Synapse.Actions.Review.ClassifyChange
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step
  alias Synapse.Workflows.ChainHelpers

  @type input :: %{
          required(:files_changed) => non_neg_integer(),
          required(:labels) => [String.t()],
          required(:intent) => String.t(),
          optional(:risk_factor) => number(),
          optional(:metadata) => map()
        }

  @doc """
  Executes the classification workflow.
  """
  @spec classify(map(), keyword()) :: {:ok, map()} | {:error, Jido.Error.t()}
  def classify(params, opts \\ [])

  def classify(params, opts) when is_map(params) do
    normalized = normalize_input(params)

    context =
      opts
      |> Keyword.get(:context)
      |> ensure_context(params)

    engine_opts =
      opts
      |> Keyword.put(:input, normalized)
      |> Keyword.put(:context, context)

    case Engine.execute(classification_spec(), engine_opts) do
      {:ok, exec} ->
        {:ok, exec.outputs.classification}

      {:error, failure} ->
        {:error, failure.error}
    end
  end

  def classify(_invalid, _opts) do
    {:error,
     Jido.Error.validation_error("classification input must be a map", %{
       required: [:files_changed, :labels, :intent]
     })}
  end

  defp normalize_input(params) do
    %{
      files_changed: fetch_param(params, :files_changed, 0),
      labels: fetch_param(params, :labels, []),
      intent: fetch_param(params, :intent, "feature"),
      risk_factor: fetch_param(params, :risk_factor, 0.0)
    }
  end

  defp fetch_param(params, key, default) do
    Map.get(params, key, Map.get(params, to_string(key), default))
  end

  defp ensure_context(nil, params) do
    %{
      request_id: ChainHelpers.generate_request_id(),
      review_id: Map.get(params, :review_id) || Map.get(params, "review_id")
    }
  end

  defp ensure_context(context, params) do
    context
    |> Map.put_new(:request_id, ChainHelpers.generate_request_id())
    |> Map.put_new(:review_id, Map.get(params, :review_id) || Map.get(params, "review_id"))
  end

  defp classification_spec do
    Spec.new(
      name: :review_classification,
      description: "Classifies review requests for coordinator routing",
      metadata: %{version: 1},
      steps: [
        Step.new(
          id: :classify,
          action: ClassifyChange,
          label: "Classify Change",
          description: "Determines fast_path vs deep_review",
          params: fn env ->
            %{
              files_changed: Map.fetch!(env.input, :files_changed),
              labels: Map.fetch!(env.input, :labels),
              intent: Map.fetch!(env.input, :intent),
              risk_factor: Map.get(env.input, :risk_factor, 0.0)
            }
          end
        )
      ],
      outputs: [
        Spec.output(:classification, from: :classify)
      ]
    )
  end
end
