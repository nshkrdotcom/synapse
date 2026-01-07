defmodule DataPipeline.Actions.Validate do
  @moduledoc """
  Validate action - validates records against rules.
  """

  use Jido.Action,
    name: "validate",
    description: "Validate records against rules",
    schema: [
      records: [
        type: :any,
        required: true,
        doc: "Records to validate"
      ],
      rules: [
        type: :any,
        default: [:not_empty, :has_content],
        doc: "Validation rules to apply"
      ],
      on_invalid: [
        type: :atom,
        default: :remove,
        doc: "What to do with invalid records: :remove, :keep, :error"
      ]
    ]

  alias DataPipeline.Record

  @impl true
  def run(params, _context) do
    records = Enum.map(params.records, &Record.from_map/1)
    rules = params.rules

    {valid, invalid} =
      Enum.split_with(records, fn record ->
        validate_record(record, rules)
      end)

    validated =
      Enum.map(valid, fn record ->
        Record.transform(record, :validate, %{rules: rules, status: :valid})
      end)

    case params.on_invalid do
      :remove ->
        {:ok, %{records: validated, count: length(validated), invalid_count: length(invalid)}}

      :keep ->
        all_records =
          validated ++
            Enum.map(invalid, fn record ->
              record
              |> Record.add_metadata(%{validation_failed: true})
              |> Record.transform(:validate, %{rules: rules, status: :invalid})
            end)

        {:ok, %{records: all_records, count: length(all_records), invalid_count: length(invalid)}}

      :error ->
        if length(invalid) > 0 do
          {:error, {:validation_failed, "#{length(invalid)} records failed validation"}}
        else
          {:ok, %{records: validated, count: length(validated), invalid_count: 0}}
        end
    end
  end

  defp validate_record(record, rules) do
    Enum.all?(rules, fn rule ->
      apply_rule(record, rule)
    end)
  end

  defp apply_rule(record, :not_empty) do
    map_size(record.content) > 0
  end

  defp apply_rule(record, :has_content) do
    has_text_field?(record.content)
  end

  defp apply_rule(record, :has_classification) do
    Map.has_key?(record.content, :classification) or
      Map.has_key?(record.content, "classification")
  end

  defp apply_rule(_record, _unknown), do: true

  defp has_text_field?(content) do
    Map.has_key?(content, :text) or
      Map.has_key?(content, "text") or
      Map.has_key?(content, :content) or
      Map.has_key?(content, "content")
  end
end
