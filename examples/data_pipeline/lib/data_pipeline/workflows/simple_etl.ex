defmodule DataPipeline.Workflows.SimpleETL do
  @moduledoc """
  Simple ETL workflow: Extract → Transform → Load

  Demonstrates a basic pipeline that extracts data, applies transformations,
  and loads the results to a destination.
  """

  alias Synapse.Workflow.{Spec, Engine}
  alias DataPipeline.Actions.{Extract, Transform, Validate, Load}

  @doc """
  Run a simple ETL pipeline.

  ## Options

    * `:batch_size` - Number of records to process per batch (default: 100)
    * `:destination` - Where to load the data (default: :memory)
    * `:transformer` - Which transformer to use (default: :summarize)
    * `:validate` - Whether to validate records (default: true)

  ## Examples

      SimpleETL.run([%{text: "Hello"}])
      SimpleETL.run(data, destination: :s3, transformer: :enrich)
  """
  @spec run(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(source_data, opts \\ []) do
    destination = Keyword.get(opts, :destination, :memory)
    transformer = Keyword.get(opts, :transformer, :summarize)
    validate? = Keyword.get(opts, :validate, true)

    # Build the workflow spec
    steps =
      [
        # Step 1: Extract
        [
          id: :extract,
          action: Extract,
          params: %{source: source_data, source_metadata: %{pipeline: :simple_etl}}
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

        # Step 3: Transform
        [
          id: :transform,
          action: Transform,
          requires: if(validate?, do: [:validate], else: [:extract]),
          params: fn env ->
            records =
              if validate? do
                env.results.validate.records
              else
                env.results.extract.records
              end

            %{records: records, transformer: transformer}
          end
        ],

        # Step 4: Load
        [
          id: :load,
          action: Load,
          requires: [:transform],
          params: fn env ->
            %{records: env.results.transform.records, destination: destination}
          end
        ]
      ]
      |> Enum.reject(&is_nil/1)

    spec =
      Spec.new(
        name: :simple_etl,
        description: "Simple ETL pipeline: Extract → Transform → Load",
        metadata: %{
          pipeline_type: :simple_etl,
          transformer: transformer,
          destination: destination
        },
        steps: steps,
        outputs: [
          [key: :count, from: :load, path: [:count]],
          [key: :destination, from: :load, path: [:destination]],
          [key: :lineage, from: :load, path: [:lineage]]
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

  defp generate_request_id do
    "simple_etl_#{:os.system_time(:millisecond)}"
  end
end
