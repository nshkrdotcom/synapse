defmodule DataPipeline.Workflows.ClassifiedPipeline do
  @moduledoc """
  Classified pipeline: Extract → Classify → Branch → Transform → Load

  Demonstrates AI-powered branching based on classification results.
  Records are classified, then routed to different transformation paths
  based on their classification.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias DataPipeline.Actions.{Extract, Classify, Transform, Validate, Load}

  @doc """
  Run a classified pipeline with AI-powered branching.

  ## Options

    * `:batch_size` - Number of records to process per batch (default: 100)
    * `:classifier` - Classifier to use: `:sentiment`, `:category`, `:intent` (default: :category)
    * `:destination` - Where to load the data (default: :memory)
    * `:validate` - Whether to validate records (default: true)

  ## Examples

      ClassifiedPipeline.run([%{text: "Customer feedback"}])

      ClassifiedPipeline.run(data,
        classifier: :sentiment,
        batch_size: 50,
        destination: :s3
      )
  """
  @spec run(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(source_data, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    classifier = Keyword.get(opts, :classifier, :category)
    destination = Keyword.get(opts, :destination, :memory)
    validate? = Keyword.get(opts, :validate, true)

    # Build the workflow spec
    steps =
      [
        # Step 1: Extract
        [
          id: :extract,
          action: Extract,
          params: %{source: source_data, source_metadata: %{pipeline: :classified}}
        ],

        # Step 2: Validate (optional)
        if validate? do
          [
            id: :validate,
            action: Validate,
            requires: [:extract],
            params: fn env ->
              %{records: env.results.extract.records, rules: [:not_empty, :has_content]}
            end
          ]
        end,

        # Step 3: AI Classification
        [
          id: :classify,
          action: Classify,
          requires: if(validate?, do: [:validate], else: [:extract]),
          params: fn env ->
            records =
              if validate? do
                env.results.validate.records
              else
                env.results.extract.records
              end

            %{
              records: records,
              classifier: classifier,
              batch_size: batch_size
            }
          end,
          retry: [max_attempts: 2, backoff: 500]
        ],

        # Step 4a: Transform high priority (enrich)
        [
          id: :transform_high,
          action: Transform,
          requires: [:classify],
          params: fn env ->
            high_priority =
              Enum.filter(env.results.classify.records, fn record ->
                get_classification(record) == :high_priority
              end)

            %{records: high_priority, transformer: :enrich}
          end,
          on_error: :continue
        ],

        # Step 4b: Transform low priority (summarize)
        [
          id: :transform_low,
          action: Transform,
          requires: [:classify],
          params: fn env ->
            low_priority =
              Enum.filter(env.results.classify.records, fn record ->
                get_classification(record) == :low_priority
              end)

            %{records: low_priority, transformer: :summarize}
          end,
          on_error: :continue
        ],

        # Step 5: Load all results
        [
          id: :load,
          action: Load,
          requires: [:transform_high, :transform_low],
          params: fn env ->
            high_records = get_records(env.results.transform_high)
            low_records = get_records(env.results.transform_low)
            all_records = high_records ++ low_records

            %{
              records: all_records,
              destination: destination,
              destination_opts: %{
                high_priority_count: length(high_records),
                low_priority_count: length(low_records)
              }
            }
          end
        ]
      ]
      |> Enum.reject(&is_nil/1)

    spec =
      Spec.new(
        name: :classified_pipeline,
        description: "Classified pipeline with AI-powered branching",
        metadata: %{
          pipeline_type: :classified,
          classifier: classifier,
          batch_size: batch_size,
          destination: destination
        },
        steps: steps,
        outputs: [
          [key: :count, from: :load, path: [:count]],
          [key: :destination, from: :load, path: [:destination]],
          [key: :lineage, from: :load, path: [:lineage]],
          [
            key: :summary,
            from: :load,
            transform: fn result, %{state: state} ->
              %{
                total_records: result.count,
                high_priority:
                  get_in(result, [:result, :high_priority_count]) ||
                    length(get_records(state.results.transform_high)),
                low_priority:
                  get_in(result, [:result, :low_priority_count]) ||
                    length(get_records(state.results.transform_low)),
                destination: result.destination
              }
            end
          ]
        ]
      )

    case Engine.execute(spec,
           input: %{source_data: source_data},
           context: %{request_id: generate_request_id()}
         ) do
      {:ok, %{outputs: outputs}} ->
        {:ok, outputs}

      {:error, failure} ->
        {:error, failure}
    end
  end

  defp get_classification(%{content: %{classification: classification}}), do: classification

  defp get_classification(%{content: %{"classification" => classification}}),
    do: classification

  defp get_classification(_), do: :low_priority

  defp get_records(%{records: records}), do: records
  defp get_records(_), do: []

  defp generate_request_id do
    "classified_pipeline_#{:os.system_time(:millisecond)}"
  end
end
