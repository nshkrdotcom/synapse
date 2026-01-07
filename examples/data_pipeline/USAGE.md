# Data Pipeline Usage Examples

Quick examples demonstrating the data pipeline capabilities.

## Run the Examples

Start an IEx session:

```bash
cd examples/data_pipeline
iex -S mix
```

## Example 1: Simple ETL Pipeline

```elixir
# Sample customer feedback data
data = [
  %{text: "Great product, very satisfied!"},
  %{text: "Terrible experience, would not recommend."},
  %{text: "Average quality, nothing special."}
]

# Run simple ETL with summarization
{:ok, result} = DataPipeline.run_simple_etl(data, transformer: :summarize)

IO.inspect(result)
# => %{
#   count: 3,
#   destination: :memory,
#   lineage: [...]
# }
```

## Example 2: Classified Pipeline with AI

```elixir
# Customer support tickets
tickets = [
  %{text: "URGENT: System down, customers cannot access!"},
  %{text: "Scheduled maintenance next Tuesday."},
  %{text: "Question: How do I reset my password?"}
]

# Run classification-based branching
{:ok, result} = DataPipeline.run_classified_pipeline(tickets,
  classifier: :category,
  batch_size: 50
)

IO.inspect(result.summary)
# => %{
#   total_records: 3,
#   high_priority: 1,  # URGENT ticket gets enriched
#   low_priority: 2,   # Others get summarized
#   destination: :memory
# }
```

## Example 3: Sentiment Analysis

```elixir
# Use sentiment classifier
feedback = DataPipeline.SampleData.customer_feedback(10)

{:ok, result} = DataPipeline.run_classified_pipeline(feedback,
  classifier: :sentiment
)

# High priority = negative sentiment (needs attention)
# Low priority = positive/neutral sentiment
```

## Example 4: Asset-First Workflow

```elixir
alias DataPipeline.Asset

# Define assets with dependencies
assets = [
  Asset.new(:raw_data,
    description: "Raw data from source",
    materializer: fn _deps ->
      {:ok, [%{value: 1}, %{value: 2}, %{value: 3}]}
    end
  ),

  Asset.new(:validated_data,
    description: "Validated data",
    deps: [:raw_data],
    materializer: fn %{raw_data: data} ->
      valid = Enum.filter(data, fn item -> item.value > 0 end)
      {:ok, valid}
    end
  ),

  Asset.new(:transformed_data,
    description: "Transformed data",
    deps: [:validated_data],
    materializer: fn %{validated_data: data} ->
      transformed = Enum.map(data, fn item ->
        Map.put(item, :doubled, item.value * 2)
      end)
      {:ok, transformed}
    end
  )
]

# Topological sort handles execution order
{:ok, sorted} = Asset.topological_sort(assets)
Enum.map(sorted, & &1.name)
# => [:raw_data, :validated_data, :transformed_data]

# Execute in order
Enum.reduce(sorted, %{}, fn asset, acc ->
  {:ok, result} = Asset.materialize(asset, acc)
  Map.put(acc, asset.name, result)
end)
```

## Example 5: Batch Processing

```elixir
alias DataPipeline.Batch

# Large dataset
records = DataPipeline.SampleData.event_logs(1000)

# Process in batches with custom logic
result = Batch.process_in_batches(records, 100, fn batch ->
  # Your processing logic here
  Enum.map(batch, fn record ->
    Map.put(record, :processed_at, DateTime.utc_now())
  end)
end, max_concurrency: 5)

length(result)
# => 1000
```

## Example 6: Lineage Tracking

```elixir
alias DataPipeline.{Record, Lineage}

# Create a record with lineage
record = Record.new(%{text: "Sample data"}, source: :api)

# Add transformations
record = record
  |> Record.transform(:extract, %{batch_id: 1})
  |> Record.transform(:classify, %{result: :high_priority})
  |> Record.transform(:enrich, %{enrichment_type: :context})
  |> Record.transform(:load, %{destination: :database})

# View the pipeline path
Lineage.pipeline_path(record.lineage)
# => [:extract, :classify, :enrich, :load]

# View full lineage
IO.inspect(record.lineage)
# Shows source, all transformations with timestamps, and metadata
```

## Example 7: Custom Classifiers

```elixir
alias DataPipeline.Classifiers.{Sentiment, Category, Intent}

# Sentiment classification
{:ok, sentiment} = Sentiment.classify("I love this product!")
# => :positive

# Category classification
{:ok, category} = Category.classify("URGENT: Critical bug!")
# => :high_priority

# Intent classification
{:ok, intent} = Intent.classify("How do I reset my password?")
# => :question

# Batch classification
texts = ["Great!", "Terrible!", "Okay"]
{:ok, sentiments} = Sentiment.classify_batch(texts)
# => [:positive, :negative, :neutral]
```

## Example 8: Custom Transformers

```elixir
alias DataPipeline.Transformers.{Summarize, Translate, Enrich}

# Summarization
long_text = "Long article text here..."
{:ok, summary} = Summarize.transform(long_text, max_length: 30)

# Translation
{:ok, translated} = Translate.transform("Hello, world!", to: "Spanish")
# => "Hola, mundo!"

# Enrichment
{:ok, enriched} = Enrich.transform("Apple released iPhone",
  enrich_with: :entities
)
# => "Apple released iPhone [Entities: Apple (Company), iPhone (Product)]"
```

## Example 9: Error Handling

```elixir
# Workflow with error handling
data = [
  %{text: "Valid data"},
  %{invalid: "no text field"},  # Will fail validation
  %{text: "More valid data"}
]

# Continue on validation errors
{:ok, result} = DataPipeline.run_simple_etl(data, validate: true)

# Check what was processed
result.count  # May be less than 3 if some failed
```

## Example 10: Sample Data Generators

```elixir
alias DataPipeline.SampleData

# Generate test data
customer_feedback = SampleData.customer_feedback(50)
event_logs = SampleData.event_logs(100)
social_posts = SampleData.social_posts(25)

# Run pipelines on generated data
{:ok, result} = DataPipeline.run_classified_pipeline(
  customer_feedback,
  classifier: :sentiment,
  batch_size: 25
)
```

## Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/data_pipeline/workflows/simple_etl_test.exs

# Run with verbose output
mix test --trace
```

## Configuration

```elixir
# config/dev.exs
config :data_pipeline,
  gemini_api_key: System.get_env("GEMINI_API_KEY")

# For production use
export GEMINI_API_KEY="your-api-key-here"
```

## Next Steps

- Explore the `/lib/data_pipeline` directory for all modules
- Read `DESIGN.md` for architecture decisions
- Check `README.md` for comprehensive documentation
- Extend with custom classifiers, transformers, and actions
