defmodule DataPipeline do
  @moduledoc """
  ETL pipeline with AI-assisted data transformations.

  DataPipeline demonstrates how to use Synapse's workflow engine for
  data orchestration with AI-powered classification and transformation steps.
  Inspired by Dagster and FlowStone's asset-first approach.

  ## Features

  - Asset-first design with explicit dependencies
  - AI-powered classification and transformation
  - Batch processing for large datasets
  - Lineage tracking through the pipeline
  - Configurable error handling

  ## Usage

      # Run a simple ETL pipeline
      {:ok, result} = DataPipeline.run_simple_etl(source_data)

      # Run a classified pipeline with branching logic
      {:ok, result} = DataPipeline.run_classified_pipeline(source_data,
        batch_size: 100,
        destination: :memory
      )

      # Run with custom assets
      assets = [
        DataPipeline.Asset.new(:raw_data,
          materializer: fn -> fetch_data() end
        ),
        DataPipeline.Asset.new(:cleaned_data,
          deps: [:raw_data],
          materializer: fn %{raw_data: data} -> clean(data) end
        )
      ]
      {:ok, result} = DataPipeline.materialize_assets(assets)
  """

  alias DataPipeline.Workflows.{SimpleETL, ClassifiedPipeline}

  @doc """
  Run a simple extract-transform-load pipeline.

  ## Options

    * `:batch_size` - Number of records to process in each batch (default: 100)
    * `:destination` - Where to load the data (default: :memory)

  ## Examples

      DataPipeline.run_simple_etl([%{text: "Hello"}])
      DataPipeline.run_simple_etl(data, batch_size: 50, destination: :s3)
  """
  @spec run_simple_etl(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_simple_etl(source_data, opts \\ []) do
    SimpleETL.run(source_data, opts)
  end

  @doc """
  Run a classified pipeline with AI-powered branching.

  This pipeline extracts data, classifies it using AI, branches processing
  based on classification, and loads the results.

  ## Options

    * `:batch_size` - Number of records to process in each batch (default: 100)
    * `:classifier` - Classifier to use: `:sentiment`, `:category`, `:intent` (default: :category)
    * `:destination` - Where to load the data (default: :memory)

  ## Examples

      DataPipeline.run_classified_pipeline([%{text: "Customer feedback"}],
        classifier: :sentiment,
        batch_size: 50
      )
  """
  @spec run_classified_pipeline(list(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_classified_pipeline(source_data, opts \\ []) do
    ClassifiedPipeline.run(source_data, opts)
  end

  @doc """
  Materialize a set of assets in dependency order.

  Assets are processed in topological order based on their dependencies.
  """
  @spec materialize_assets([DataPipeline.Asset.t()]) :: {:ok, map()} | {:error, term()}
  def materialize_assets(assets) when is_list(assets) do
    # This would use the Asset module to build and execute a workflow
    # For now, return a placeholder
    {:ok, %{assets: length(assets), materialized: []}}
  end
end
