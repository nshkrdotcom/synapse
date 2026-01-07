# Data Pipeline Design Document

## Overview

This example demonstrates how to build ETL pipelines with AI-assisted transformations using Synapse's workflow orchestration. It showcases asset-first design principles inspired by Dagster and FlowStone, combined with AI capabilities for intelligent data processing.

## Design Goals

1. **Asset-First Architecture**: Data artifacts as first-class citizens
2. **AI Integration**: Seamless integration of AI for classification and transformation
3. **Lineage Tracking**: Automatic provenance tracking through the pipeline
4. **Batch Processing**: Efficient handling of large datasets
5. **Composability**: Reusable actions that can be combined into workflows
6. **Testability**: Easy to test with mocked AI providers

## Architecture Decisions

### 1. Asset-First Design (Inspired by FlowStone/Dagster)

**Decision**: Model data as assets with explicit dependencies rather than imperative task sequences.

**Rationale**:
- Makes data dependencies explicit and verifiable at compile time
- Enables automatic topological sorting for execution order
- Supports impact analysis ("what breaks if this changes?")
- Facilitates partial re-execution and caching
- Provides clear mental model for data lineage

**Implementation**:
```elixir
# Assets declare what they depend on
Asset.new(:cleaned_data,
  deps: [:raw_data],
  materializer: fn %{raw_data: data} -> clean(data) end
)

# Framework handles execution order
{:ok, sorted} = Asset.topological_sort(assets)
```

**Trade-offs**:
- Pro: Clear dependency graph, automatic ordering
- Pro: Easy to visualize and understand
- Con: More verbose than simple function composition
- Con: Requires upfront design of asset structure

### 2. Lineage as a First-Class Concept

**Decision**: Every record carries its own lineage information throughout the pipeline.

**Rationale**:
- Enables debugging ("where did this bad data come from?")
- Supports compliance and audit requirements
- Makes data provenance queryable
- Helps with reproducibility

**Implementation**:
```elixir
# Lineage is embedded in each record
record = Record.new(data, source: :api)
record = Record.transform(record, :classify, metadata)

# Full history is preserved
Lineage.pipeline_path(record.lineage)
# => [:extract, :classify, :transform, :load]
```

**Trade-offs**:
- Pro: Complete audit trail
- Pro: Self-contained records
- Con: Increased memory overhead per record
- Con: Lineage data grows with pipeline depth

**Mitigation**: For very long pipelines, implement lineage pruning or external storage.

### 3. Batch Processing Strategy

**Decision**: Process records in configurable batches with parallel execution.

**Rationale**:
- AI APIs often have rate limits
- Batching reduces number of API calls
- Parallelism improves throughput
- Configurable batch size allows tuning for specific workloads

**Implementation**:
```elixir
Batch.process_in_batches(records, batch_size, processor,
  max_concurrency: 10,
  timeout: 60_000
)
```

**Design Considerations**:

**Batch Size**:
- Too small: High overhead, many API calls
- Too large: Poor error isolation, memory pressure
- Recommended: 50-100 for most AI workloads

**Concurrency**:
- Limited by rate limits of AI providers
- Consider provider-specific pools
- Use semaphores for strict rate limiting

**Error Handling**:
- Per-batch errors vs. per-record errors
- Retry strategies (exponential backoff)
- Dead letter queues for failed batches

### 4. AI Provider Abstraction

**Decision**: Define a behaviour for AI providers to enable testing and provider switching.

**Rationale**:
- Tests shouldn't depend on external AI services
- Should be able to switch providers (Gemini → OpenAI → Claude)
- Mock implementations for deterministic tests

**Implementation**:
```elixir
@behaviour DataPipeline.Providers.Behaviour

# Production
defmodule Providers.Gemini do
  def generate(prompt, opts), do: call_gemini_api(prompt, opts)
end

# Testing
config :data_pipeline, use_mocks: true

# Mock returns deterministic results based on prompt content
```

**Trade-offs**:
- Pro: Testable without API keys
- Pro: Fast tests
- Pro: Easy to add new providers
- Con: Behaviour must be general enough for all providers
- Con: Mocks may diverge from real behavior

### 5. Workflow Composition with Synapse

**Decision**: Use Synapse's declarative workflow specs rather than imperative code.

**Rationale**:
- Declarative specs are easier to visualize and understand
- Built-in retry, error handling, and telemetry
- Can persist workflow state for debugging
- Supports conditional steps and branching

**Implementation**:
```elixir
Spec.new(
  name: :classified_pipeline,
  steps: [
    [id: :extract, action: Extract, params: %{...}],
    [id: :classify, action: Classify, requires: [:extract]],
    [id: :transform_high, requires: [:classify], on_error: :continue],
    [id: :transform_low, requires: [:classify], on_error: :continue],
    [id: :load, requires: [:transform_high, :transform_low]]
  ],
  outputs: [...]
)
```

**Benefits**:
- Clear execution graph
- Automatic dependency resolution
- Built-in error handling
- Telemetry integration
- Audit trail generation

### 6. Classification-Based Branching

**Decision**: Use AI classification to route records to different transformation paths.

**Rationale**:
- Different record types need different processing
- AI can intelligently categorize unstructured data
- Demonstrates workflow branching capabilities

**Implementation**:
```elixir
# Classify records
[id: :classify, action: Classify, params: %{classifier: :category}]

# Branch based on classification
[id: :transform_high,
 params: fn env ->
   high = Enum.filter(env.results.classify.records,
     &(&1.classification == :high_priority))
   %{records: high, transformer: :enrich}
 end]

[id: :transform_low,
 params: fn env ->
   low = Enum.filter(env.results.classify.records,
     &(&1.classification == :low_priority))
   %{records: low, transformer: :summarize}
 end]
```

**Use Cases**:
- Customer feedback: Route negative feedback to support team
- Event logs: Different handling for errors vs. info logs
- Content moderation: Flag problematic content for review

### 7. Data Structure Decisions

#### Record Structure
```elixir
%Record{
  id: "unique_id",
  content: %{...},        # Actual data
  lineage: %Lineage{},    # Provenance tracking
  metadata: %{}           # Additional annotations
}
```

**Why separate content from metadata?**
- Content is the actual data being processed
- Metadata is about the processing itself
- Lineage is specifically about provenance
- Clear separation of concerns

#### Lineage Structure
```elixir
%Lineage{
  record_id: "...",
  source: :api,
  source_metadata: %{endpoint: "..."},
  transformations: [
    %{step: :extract, timestamp: ~U[...], metadata: %{...}},
    %{step: :classify, timestamp: ~U[...], metadata: %{...}}
  ],
  created_at: ~U[...]
}
```

**Design choices**:
- Transformations as list preserves order
- Timestamps enable duration calculations
- Metadata per step enables detailed tracking
- Immutable structure prevents tampering

### 8. Error Handling Strategy

**Decision**: Multiple levels of error handling with configurable behavior.

**Levels**:

1. **Action-level**: Jido action validation and error returns
2. **Step-level**: Synapse workflow `on_error: :continue` or `:halt`
3. **Batch-level**: Continue processing other batches on error
4. **Record-level**: Mark failed records but continue pipeline

**Implementation**:
```elixir
# Step continues on error
[id: :transform_high, on_error: :continue]

# Batch processing handles individual failures
Batch.process_in_batches(records, 100, fn batch ->
  Enum.map(batch, fn record ->
    case transform(record) do
      {:ok, result} -> result
      {:error, _} -> mark_failed(record)
    end
  end)
end)
```

**Configuration**:
```elixir
# Validation can remove, keep, or error on invalid records
[id: :validate, params: %{on_invalid: :remove}]
```

### 9. Testing Strategy

**Decision**: Use mocks for AI providers and test at multiple levels.

**Test Levels**:

1. **Unit Tests**: Individual components (Asset, Lineage, Batch)
2. **Integration Tests**: Actions with mocked providers
3. **Workflow Tests**: End-to-end pipeline execution
4. **Property Tests**: (Future) Generative testing of lineage properties

**Mock Strategy**:
```elixir
# config/test.exs
config :data_pipeline, use_mocks: true

# Provider implementation
def generate(prompt, _opts) do
  if Application.get_env(:data_pipeline, :use_mocks) do
    mock_generate(prompt)
  else
    real_generate(prompt)
  end
end

# Mock returns deterministic results
defp mock_generate(prompt) do
  cond do
    String.contains?(prompt, "sentiment") -> {:ok, "positive"}
    String.contains?(prompt, "category") -> {:ok, "high_priority"}
    true -> {:ok, "default_response"}
  end
end
```

**Benefits**:
- Fast test execution (no API calls)
- Deterministic results
- No API keys required for CI/CD
- Can test error scenarios

**Limitations**:
- Mocks may not reflect real AI behavior
- Should periodically test against real providers
- Consider contract testing for provider interface

## Performance Considerations

### Batch Size Optimization

**Factors**:
- API rate limits (requests per second)
- API cost (cost per request)
- Memory constraints
- Latency requirements
- Error granularity

**Recommendations**:
- Start with 100 records per batch
- Monitor API costs and adjust
- Consider provider-specific batching (some support batch endpoints)
- Use smaller batches for expensive operations
- Use larger batches for cheap operations

### Concurrency Tuning

**Trade-offs**:
```elixir
# More concurrency = faster, but:
# - Higher memory usage
# - Risk of rate limiting
# - Harder to debug

# Less concurrency = slower, but:
# - Lower memory usage
# - Easier to debug
# - Simpler error handling
```

**Configuration**:
```elixir
# Conservative (good for development)
max_concurrency: 2

# Moderate (good for production)
max_concurrency: 10

# Aggressive (only if provider supports)
max_concurrency: 50
```

### Memory Management

**Concerns**:
- Each record carries lineage (overhead)
- Batches held in memory during processing
- Large datasets may not fit in memory

**Strategies**:
1. **Stream Processing**: Process records as streams, not lists
2. **Lineage Pruning**: Remove old transformations after N steps
3. **External Lineage Storage**: Store lineage in database, not memory
4. **Chunking**: Process data in chunks, write intermediate results

**Example**:
```elixir
# Stream-based processing (future enhancement)
File.stream!("input.jsonl")
|> Stream.map(&Jason.decode!/1)
|> Stream.chunk_every(100)
|> Stream.map(&process_batch/1)
|> Stream.into(File.stream!("output.jsonl"))
|> Stream.run()
```

## Future Enhancements

### 1. Checkpoint and Resume

**Idea**: Save pipeline state to resume after failures.

```elixir
# Save checkpoint after each step
checkpoint = Checkpoint.save(workflow_state)

# Resume from checkpoint
Workflow.resume(checkpoint)
```

**Use cases**:
- Long-running pipelines
- Expensive AI operations
- Network failures

### 2. Asset Caching

**Idea**: Cache materialized assets to avoid recomputation.

```elixir
Asset.new(:expensive_computation,
  materializer: fn deps -> compute(deps) end,
  cache: [
    enabled: true,
    ttl: :timer.hours(24),
    key: fn deps -> cache_key(deps) end
  ]
)
```

### 3. Incremental Processing

**Idea**: Only process new/changed records.

```elixir
# Track which records have been processed
Asset.new(:daily_report,
  partitioned_by: :date,
  materializer: fn %{events: events} ->
    # Only process today's events
    events
    |> filter_by_partition(context.partition)
    |> aggregate()
  end
)
```

### 4. Human-in-the-Loop

**Idea**: Pause pipeline for human approval.

```elixir
[id: :review, action: HumanReview,
 params: %{
   review_type: :classification_confidence,
   threshold: 0.8,
   timeout: :timer.hours(1)
 }]
```

### 5. Multi-Provider Ensemble

**Idea**: Use multiple AI providers and aggregate results.

```elixir
[id: :classify_ensemble,
 params: fn env ->
   %{
     records: env.results.extract.records,
     providers: [:gemini, :openai, :claude],
     aggregation: :majority_vote
   }
 end]
```

### 6. Cost Tracking

**Idea**: Track API costs per pipeline run.

```elixir
# After pipeline completion
cost_report = %{
  total_api_calls: 150,
  total_tokens: 45_000,
  estimated_cost_usd: 0.23,
  cost_by_step: %{
    classify: 0.15,
    transform: 0.08
  }
}
```

## Comparison with Other Approaches

### vs. Imperative Pipeline

**Imperative**:
```elixir
def process(data) do
  data
  |> extract()
  |> classify()
  |> transform()
  |> load()
end
```

**Asset-First**:
```elixir
assets = [
  Asset.new(:raw, materializer: fn _ -> extract() end),
  Asset.new(:classified, deps: [:raw], materializer: fn %{raw: r} -> classify(r) end),
  Asset.new(:transformed, deps: [:classified], materializer: fn %{classified: c} -> transform(c) end),
  Asset.new(:loaded, deps: [:transformed], materializer: fn %{transformed: t} -> load(t) end)
]
```

**Trade-offs**:
- Imperative: Simpler, less overhead
- Asset-first: More explicit, better for complex dependencies

### vs. Plain Synapse Workflows

**This Example** (with domain models):
```elixir
DataPipeline.run_classified_pipeline(data)
```

**Plain Synapse** (direct workflow spec):
```elixir
Spec.new(steps: [...])
|> Engine.execute()
```

**This example adds**:
- Domain-specific abstractions (Asset, Record, Lineage)
- AI provider integration
- Batch processing utilities
- Lineage tracking

## Conclusion

This example demonstrates how Synapse's workflow engine can be used to build sophisticated data pipelines with:

- **Clear data lineage**: Every record knows where it came from
- **AI integration**: Intelligent classification and transformation
- **Efficient processing**: Batch and parallel execution
- **Testability**: Mocked providers for fast tests
- **Flexibility**: Composable actions and configurable workflows

The asset-first approach provides a solid foundation for complex data orchestration while maintaining simplicity for common use cases.
