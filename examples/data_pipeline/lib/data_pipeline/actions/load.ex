defmodule DataPipeline.Actions.Load do
  @moduledoc """
  Load action - loads records to a destination.
  """

  use Jido.Action,
    name: "load",
    description: "Load records to destination",
    schema: [
      records: [
        type: :any,
        required: true,
        doc: "Records to load"
      ],
      destination: [
        type: :any,
        default: :memory,
        doc: "Destination: :memory, :database, :s3, etc."
      ],
      destination_opts: [
        type: :map,
        default: %{},
        doc: "Destination-specific options"
      ]
    ]

  alias DataPipeline.Record

  @impl true
  def run(params, _context) do
    records = Enum.map(params.records, &Record.from_map/1)
    destination = params.destination

    # Add load transformation to lineage
    records_with_load =
      Enum.map(records, fn record ->
        Record.transform(record, :load, %{destination: destination})
      end)

    # Actually load the data
    case load_to_destination(records_with_load, destination, params.destination_opts) do
      {:ok, result} ->
        lineage = Enum.map(records_with_load, & &1.lineage)

        {:ok,
         %{
           count: length(records_with_load),
           destination: destination,
           lineage: lineage,
           result: result
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_to_destination(records, :memory, _opts) do
    # Store in process dictionary for testing/demo
    Process.put(:loaded_records, records)
    {:ok, %{stored: :memory, count: length(records)}}
  end

  defp load_to_destination(records, :database, opts) do
    # Would insert into database here
    table = Map.get(opts, :table, "records")
    {:ok, %{stored: :database, table: table, count: length(records)}}
  end

  defp load_to_destination(records, :s3, opts) do
    # Would upload to S3 here
    bucket = Map.get(opts, :bucket, "data-pipeline")
    path = Map.get(opts, :path, "records.json")
    {:ok, %{stored: :s3, bucket: bucket, path: path, count: length(records)}}
  end

  defp load_to_destination(records, :file, opts) do
    # Would write to file here
    path = Map.get(opts, :path, "output.json")
    {:ok, %{stored: :file, path: path, count: length(records)}}
  end

  defp load_to_destination(_records, destination, _opts) do
    {:error, {:unsupported_destination, destination}}
  end
end
