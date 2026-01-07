defmodule DataPipeline.Actions.Transform do
  @moduledoc """
  Transform action - uses AI to transform record content.
  """

  use Jido.Action,
    name: "transform",
    description: "Transform records using AI",
    schema: [
      records: [
        type: :any,
        required: true,
        doc: "Records to transform"
      ],
      transformer: [
        type: :atom,
        required: true,
        doc: "Transformer to use: :summarize, :translate, :enrich"
      ],
      transformer_opts: [
        type: :map,
        default: %{},
        doc: "Options to pass to the transformer"
      ]
    ]

  alias DataPipeline.{Record, Transformers}

  @impl true
  def run(params, _context) do
    transformer = resolve_transformer(params.transformer)
    records = Enum.map(params.records, &Record.from_map/1)
    opts = Map.to_list(params.transformer_opts)

    transformed =
      Enum.map(records, fn record ->
        text = get_text(record.content)

        case transformer.transform(text, opts) do
          {:ok, result} ->
            record
            |> Record.merge_content(%{transformed_text: result})
            |> Record.transform(:transform, %{
              transformer: params.transformer,
              opts: params.transformer_opts
            })

          {:error, _reason} ->
            # Keep original on error
            record
            |> Record.add_metadata(%{transform_error: true})
        end
      end)

    {:ok, %{records: transformed, count: length(transformed)}}
  end

  defp resolve_transformer(:summarize), do: Transformers.Summarize
  defp resolve_transformer(:translate), do: Transformers.Translate
  defp resolve_transformer(:enrich), do: Transformers.Enrich

  defp get_text(%{text: text}), do: text
  defp get_text(%{"text" => text}), do: text
  defp get_text(%{content: content}), do: content
  defp get_text(%{"content" => content}), do: content
  defp get_text(other) when is_binary(other), do: other
  defp get_text(other), do: inspect(other)
end
