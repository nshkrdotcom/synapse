defmodule DataPipeline.Actions.Extract do
  @moduledoc """
  Extract action - loads data from a source and wraps it in Record structs.
  """

  use Jido.Action,
    name: "extract",
    description: "Extract data from source and create records with lineage",
    schema: [
      source: [
        type: :any,
        required: true,
        doc: "Data source: list of items, :database, :api, etc."
      ],
      source_metadata: [
        type: :map,
        default: %{},
        doc: "Metadata about the source"
      ]
    ]

  alias DataPipeline.Record

  @impl true
  def run(params, _context) do
    source_data = resolve_source(params.source)
    source_name = get_source_name(params.source)
    metadata = params.source_metadata

    records =
      Record.new_batch(source_data,
        source: source_name,
        metadata: metadata
      )

    {:ok, %{records: records, count: length(records), source: source_name}}
  end

  defp resolve_source(data) when is_list(data), do: data
  defp resolve_source(:database), do: fetch_from_database()
  defp resolve_source(:api), do: fetch_from_api()
  defp resolve_source(:file), do: fetch_from_file()
  defp resolve_source(other), do: raise("Unknown source: #{inspect(other)}")

  defp get_source_name(data) when is_list(data), do: :memory
  defp get_source_name(atom) when is_atom(atom), do: atom
  defp get_source_name(string) when is_binary(string), do: String.to_atom(string)

  # Placeholder implementations
  defp fetch_from_database do
    # Would query database here
    []
  end

  defp fetch_from_api do
    # Would call API here
    []
  end

  defp fetch_from_file do
    # Would read file here
    []
  end
end
