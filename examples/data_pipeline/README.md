# Data Pipeline Example

ETL pipeline with AI-assisted data transformations, demonstrating Synapse's workflow orchestration capabilities with asset-first design inspired by Dagster and FlowStone.

## Features

- **Asset-First Design**: Define data assets with explicit dependencies
- **AI Classification**: Classify data using Gemini for fast, intelligent categorization
- **AI Transformation**: Transform and enrich data with AI-powered operations
- **Batch Processing**: Efficiently process large datasets in configurable batches
- **Lineage Tracking**: Automatic data provenance tracking through the entire pipeline
- **Configurable Workflows**: Build complex pipelines with branching and error handling

## Quick Start

### Installation

```bash
cd examples/data_pipeline
mix deps.get
mix compile
```

### Running Tests

```bash
mix test
```

### Basic Usage

```elixir
# Simple ETL pipeline
data = [
  %{text: "Customer complaint about slow service"},
  %{text: "Thank you for the great support!"},
  %{text: "URGENT: System down, need immediate help"}
]

{:ok, result} = DataPipeline.run_simple_etl(data)
# => %{count: 3, destination: :memory, lineage: [...]}

# Classified pipeline with AI-powered branching
{:ok, result} = DataPipeline.run_classified_pipeline(data,
  classifier: :sentiment,
  batch_size: 100,
  destination: :memory
)
# => %{
#   count: 3,
#   summary: %{
#     total_records: 3,
#     high_priority: 1,
#     low_priority: 2,
#     destination: :memory
#   },
#   lineage: [...]
# }
```

## Architecture

### Workflows

#### Simple ETL
Basic extract → transform → load pipeline:

```elixir
DataPipeline.run_simple_etl(data,
  transformer: :summarize,
  destination: :s3,
  validate: true
)
```

Flow: **Extract** → **Validate** → **Transform** → **Load**

#### Classified Pipeline
AI-powered branching based on classification:

```elixir
DataPipeline.run_classified_pipeline(data,
  classifier: :category,
  batch_size: 50
)
```

Flow:
```
Extract → Validate → Classify
                       ├─ High Priority → Enrich → ┐
                       └─ Low Priority → Summarize → Load
```

### Core Components

#### Asset
Defines a data artifact with dependencies:

```elixir
alias DataPipeline.Asset

asset = Asset.new(:cleaned_events,
  description: "Validated and cleaned events",
  deps: [:raw_events],
  materializer: fn %{raw_events: events} ->
    {:ok, clean_and_validate(events)}
  end
)
```

#### Record
Wraps data with lineage tracking:

```elixir
alias DataPipeline.Record

record = Record.new(%{text: "Hello"}, source: :api)
record = Record.transform(record, :classify, %{result: :positive})
```

#### Lineage
Tracks data provenance:

```elixir
alias DataPipeline.Lineage

lineage = Lineage.new(:database, %{table: "events"})
lineage = Lineage.add_transformation(lineage, :extract)
lineage = Lineage.add_transformation(lineage, :classify, %{result: :high})

Lineage.pipeline_path(lineage)
# => [:extract, :classify]
```

#### Batch Processing
Efficient parallel processing:

```elixir
alias DataPipeline.Batch

Batch.process_in_batches(records, 100, fn batch ->
  Enum.map(batch, &transform/1)
end, max_concurrency: 10)
```

### AI Components

#### Classifiers
- **Sentiment**: Positive, negative, or neutral
- **Category**: High priority or low priority
- **Intent**: Question, statement, request, or complaint

```elixir
alias DataPipeline.Classifiers.Sentiment

{:ok, :positive} = Sentiment.classify("I love this product!")
```

#### Transformers
- **Summarize**: Generate concise summaries
- **Translate**: Translate between languages
- **Enrich**: Add context and metadata

```elixir
alias DataPipeline.Transformers.Summarize

{:ok, summary} = Summarize.transform(long_text, max_length: 50)
```

### Actions

All actions are Jido Actions that can be composed into workflows:

- `Extract`: Load data from sources
- `Classify`: AI-powered classification
- `Transform`: AI-powered transformation
- `Validate`: Rule-based validation
- `Load`: Store results to destinations

## Configuration

### Environment Variables

```bash
# Required for AI features
export GEMINI_API_KEY="your-api-key"
```

### Config Files

```elixir
# config/dev.exs
config :data_pipeline,
  gemini_api_key: System.get_env("GEMINI_API_KEY"),
  gemini_available: !is_nil(System.get_env("GEMINI_API_KEY"))

config :data_pipeline, DataPipeline.Batch,
  default_batch_size: 100,
  max_parallel_batches: 10
```

## Examples

### Customer Feedback Pipeline

```elixir
# Classify feedback by sentiment and route accordingly
feedback = DataPipeline.SampleData.customer_feedback(100)

{:ok, result} = DataPipeline.run_classified_pipeline(feedback,
  classifier: :sentiment,
  batch_size: 50,
  destination: :database
)

IO.inspect(result.summary)
# => %{
#   total_records: 100,
#   high_priority: 35,  # Negative sentiment
#   low_priority: 65,   # Positive/neutral
#   destination: :database
# }
```

### Event Log Processing

```elixir
# Extract, classify, and enrich event logs
logs = DataPipeline.SampleData.event_logs(1000)

{:ok, result} = DataPipeline.run_classified_pipeline(logs,
  classifier: :category,
  batch_size: 100,
  destination: :s3
)
```

### Custom Asset Pipeline

```elixir
alias DataPipeline.Asset

# Define assets with dependencies
raw = Asset.new(:raw_data,
  materializer: fn _ -> {:ok, fetch_data()} end
)

cleaned = Asset.new(:cleaned_data,
  deps: [:raw_data],
  materializer: fn %{raw_data: data} ->
    {:ok, Enum.filter(data, &valid?/1)}
  end
)

enriched = Asset.new(:enriched_data,
  deps: [:cleaned_data],
  materializer: fn %{cleaned_data: data} ->
    {:ok, Enum.map(data, &enrich/1)}
  end
)

# Topologically sort and execute
{:ok, sorted} = Asset.topological_sort([enriched, raw, cleaned])
# => [raw, cleaned, enriched]
```

## Testing

The example includes comprehensive tests with mocked AI providers:

```bash
# Run all tests
mix test

# Run specific test file
mix test test/data_pipeline/workflows/simple_etl_test.exs

# Run with coverage
mix test --cover
```

Tests use mock implementations of AI providers for fast, deterministic results.

## Performance Considerations

### Batch Size Tuning

```elixir
# Small batches: Better error isolation, more overhead
DataPipeline.run_classified_pipeline(data, batch_size: 10)

# Large batches: Better throughput, less error resilience
DataPipeline.run_classified_pipeline(data, batch_size: 500)

# Recommended: 50-100 for most use cases
DataPipeline.run_classified_pipeline(data, batch_size: 100)
```

### Concurrency Control

```elixir
alias DataPipeline.Batch

# Control parallel batch processing
Batch.process_in_batches(records, 100, processor,
  max_concurrency: 5,  # Limit concurrent batches
  timeout: 30_000      # 30 second timeout per batch
)
```

## See Also

- [DESIGN.md](DESIGN.md) - Architecture decisions and rationale
- [Synapse Documentation](../../README.md) - Main framework docs
- [FlowStone](../../../flowstone/README.md) - Asset-first orchestration inspiration
- [Jido Actions](https://hexdocs.pm/jido) - Action framework used for steps

## License

Same as parent project.
