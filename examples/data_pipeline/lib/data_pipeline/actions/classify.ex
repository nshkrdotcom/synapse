defmodule DataPipeline.Actions.Classify do
  @moduledoc """
  Classify action - uses AI to classify records in batches.
  """

  use Jido.Action,
    name: "classify",
    description: "Classify records using AI",
    schema: [
      records: [
        type: :any,
        required: true,
        doc: "Records to classify"
      ],
      classifier: [
        type: :atom,
        required: true,
        doc: "Classifier to use: :sentiment, :category, :intent"
      ],
      batch_size: [
        type: :integer,
        default: 50,
        doc: "Number of records to process per batch"
      ]
    ]

  alias DataPipeline.{Batch, Record, Classifiers}

  @impl true
  def run(params, _context) do
    classifier = resolve_classifier(params.classifier)
    records = Enum.map(params.records, &Record.from_map/1)

    classified =
      Batch.process_in_batches(
        records,
        params.batch_size,
        fn batch ->
          classify_batch(batch, classifier, params.classifier)
        end
      )

    case classified do
      {:error, reason} ->
        {:error, reason}

      results ->
        records_with_classification = List.flatten(results)
        {:ok, %{records: records_with_classification, count: length(records_with_classification)}}
    end
  end

  defp classify_batch(batch, classifier_module, classifier_name) do
    texts = Enum.map(batch, fn record -> get_text(record.content) end)

    case classifier_module.classify_batch(texts) do
      {:ok, classifications} ->
        Enum.zip(batch, classifications)
        |> Enum.map(fn {record, classification} ->
          record
          |> Record.merge_content(%{classification: classification})
          |> Record.transform(:classify, %{
            classifier: classifier_name,
            result: classification
          })
        end)

      {:error, _reason} ->
        # Fallback to individual classification
        Enum.map(batch, fn record ->
          text = get_text(record.content)

          {:ok, classification} = classifier_module.classify(text)

          record
          |> Record.merge_content(%{classification: classification})
          |> Record.transform(:classify, %{
            classifier: classifier_name,
            result: classification
          })
        end)
    end
  end

  defp resolve_classifier(:sentiment), do: Classifiers.Sentiment
  defp resolve_classifier(:category), do: Classifiers.Category
  defp resolve_classifier(:intent), do: Classifiers.Intent

  defp get_text(%{text: text}), do: text
  defp get_text(%{"text" => text}), do: text
  defp get_text(%{content: content}), do: content
  defp get_text(%{"content" => content}), do: content
  defp get_text(other) when is_binary(other), do: other
  defp get_text(other), do: inspect(other)
end
