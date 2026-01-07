# Research Agent

A multi-provider research assistant demonstrating Synapse's workflow orchestration capabilities.

## Features

- **Cascade Workflows**: Fast queries with Gemini, deep synthesis with Claude
- **Multi-step Research**: Query → Search → Gather → Summarize → Synthesize
- **Source Tracking**: Automatic reliability scoring and citation management
- **Provider Fallback**: Seamless fallback between AI providers
- **Flexible Depth**: Quick, deep, or comprehensive research modes

## Installation

```bash
cd examples/research_agent
mix deps.get
```

## Configuration

Set API keys for the providers you want to use:

```bash
export GEMINI_API_KEY="your-gemini-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
```

At least one provider must be configured. The agent will automatically use available providers.

## Usage

### Quick Research

Fast research using a single provider (default: Gemini):

```elixir
# Start the application
iex -S mix

# Simple research query
{:ok, result} = ResearchAgent.research("What is quantum computing?")

# Access the results
IO.puts(result.outputs.content)
# => Comprehensive explanation of quantum computing...

# View sources
result.outputs.sources
# => [%Source{url: "...", title: "...", reliability_score: 0.85}, ...]

# Check provider used
result.outputs.provider
# => :gemini
```

### Deep Research

Multi-step research with cascade fallback:

```elixir
# Deep research with more sources
{:ok, result} = ResearchAgent.research(
  "Impact of artificial intelligence on healthcare",
  depth: :deep,
  max_sources: 15
)

# View comprehensive synthesis
IO.puts(result.outputs.content)

# Check metadata
result.outputs.metadata
# => %{
#   search_provider: :gemini,
#   synthesis_provider: :claude,
#   source_count: 12,
#   total_found: 15,
#   workflow_type: :deep_research
# }
```

### Comprehensive Research

Maximum depth with all available features:

```elixir
{:ok, result} = ResearchAgent.research(
  "Climate change mitigation strategies",
  depth: :comprehensive,
  max_sources: 20,
  reliability_threshold: 0.7,
  include_citations: true
)
```

### Provider Override

Explicitly choose a provider:

```elixir
# Use Claude for everything (if available)
{:ok, result} = ResearchAgent.research(
  "Machine learning explainability",
  provider: :claude
)

# Use Gemini for everything (if available)
{:ok, result} = ResearchAgent.research(
  "Neural network architectures",
  provider: :gemini
)
```

### Check Available Providers

```elixir
# List all available providers
ResearchAgent.available_providers()
# => [:gemini, :claude]

# Check specific provider
ResearchAgent.provider_available?(:gemini)
# => true
```

## API Reference

### ResearchAgent.research/2

Main entry point for research queries.

**Arguments:**
- `topic` (String.t) - The research topic or question
- `opts` (keyword) - Options

**Options:**
- `:depth` - Research depth: `:quick`, `:deep`, or `:comprehensive` (default: `:quick`)
- `:max_sources` - Maximum sources to gather (default: 10)
- `:reliability_threshold` - Minimum source reliability score 0.0-1.0 (default: 0.6)
- `:include_citations` - Include detailed citations (default: true)
- `:provider` - Override provider selection (`:gemini` or `:claude`)

**Returns:**
- `{:ok, result}` - Successful research with outputs
- `{:error, reason}` - Failure reason

**Result Structure:**

```elixir
%{
  results: %{...},           # Raw workflow results
  outputs: %{
    content: "...",          # Synthesized research text
    provider: :claude,       # Provider used for synthesis
    sources: [...],          # List of Source structs
    source_count: 8,         # Number of sources used
    metadata: %{...}         # Additional metadata
  },
  audit_trail: %{...}        # Workflow execution audit
}
```

## Architecture

### Workflows

**QuickResearch** (`lib/research_agent/workflows/quick_research.ex`)
- Single-provider workflow optimized for speed
- Steps: Search → Fetch → Synthesize
- Use case: Fast answers to straightforward questions

**DeepResearch** (`lib/research_agent/workflows/deep_research.ex`)
- Multi-provider workflow with cascade fallback
- Steps: Search → Fetch → Summarize → Synthesize
- Use case: Comprehensive research requiring deep analysis

### Actions

All workflow steps are implemented as Jido Actions:

- **SearchWeb** - Search for sources using AI provider
- **FetchContent** - Convert search results to Source structs
- **Summarize** - Create concise summaries
- **Synthesize** - Generate final research output

### Providers

**Gemini** (`lib/research_agent/providers/gemini.ex`)
- Fast search and summarization
- Large context windows
- Model: gemini-2.0-flash-exp

**Claude** (`lib/research_agent/providers/claude.ex`)
- Deep synthesis and analysis
- High-quality structured outputs
- Model: claude-opus-4-5-20251101

### Source Reliability

Sources are automatically scored based on:
- Domain reputation (.edu, .gov, .org receive higher scores)
- Content length and quality
- Metadata completeness

Only sources above the `reliability_threshold` are used in synthesis.

## Examples

### Example 1: Scientific Topic

```elixir
{:ok, result} = ResearchAgent.research(
  "CRISPR gene editing applications",
  depth: :deep,
  max_sources: 12,
  reliability_threshold: 0.7
)

# High-quality sources from academic institutions
Enum.each(result.outputs.sources, fn source ->
  IO.puts("#{source.title} (score: #{source.reliability_score})")
  IO.puts("  #{source.url}\n")
end)
```

### Example 2: Current Events

```elixir
{:ok, result} = ResearchAgent.research(
  "Renewable energy trends 2024",
  depth: :comprehensive,
  max_sources: 15
)

# Save the research to a file
File.write!("research_output.md", result.outputs.content)
```

### Example 3: Technical Documentation

```elixir
{:ok, result} = ResearchAgent.research(
  "Elixir GenServer best practices",
  provider: :gemini,  # Fast provider for technical docs
  include_citations: false
)

IO.puts(result.outputs.content)
```

## Development

### Running Tests

```bash
mix test
```

### Type Checking

```bash
mix dialyzer
```

### Code Formatting

```bash
mix format
```

## Design Decisions

See [DESIGN.md](DESIGN.md) for detailed architecture decisions, cascade strategy explanation, and future enhancements.

## Key Patterns Demonstrated

1. **Cascade Workflows**: Provider fallback for reliability
2. **Multi-step Pipelines**: Complex workflows with dependencies
3. **Dynamic Parameters**: Using functions to resolve step params from previous results
4. **Source Tracking**: Managing and scoring information sources
5. **Error Handling**: Retry strategies and graceful degradation
6. **Composable Actions**: Reusable Jido actions across workflows

## Limitations

This is an example application demonstrating Synapse patterns. Production use would require:

1. **Real Search API Integration**: Currently uses simulated search results
2. **Content Fetching**: Actual HTTP requests to fetch source content
3. **Caching**: Cache search results and syntheses
4. **Rate Limiting**: Respect API rate limits
5. **Error Recovery**: More sophisticated error handling
6. **Persistence**: Store research history and results

## Contributing

This example is part of the Synapse framework. See the main repository for contribution guidelines.

## License

Same as Synapse framework.
