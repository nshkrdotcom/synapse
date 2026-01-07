# Research Agent Design Document

## Overview

The Research Agent is an example application demonstrating Synapse's multi-agent orchestration capabilities for research and information synthesis tasks. It showcases:

- **Cascade workflow patterns** for provider fallback
- **Multi-step research pipelines** with dependency management
- **Source tracking and reliability scoring**
- **AI provider integration** (Gemini and Claude)

## Architecture

### Core Components

#### 1. Query & Source Structs

**Query** (`lib/research_agent/query.ex`)
- Encapsulates research parameters (topic, depth, source limits)
- Tracks reliability thresholds and citation preferences
- Generates unique IDs for request tracking

**Source** (`lib/research_agent/source.ex`)
- Represents individual research sources
- Automatic reliability scoring based on:
  - Domain reputation (.edu, .gov, .org)
  - Content length and quality signals
  - Metadata completeness
- Citation formatting capabilities

#### 2. Provider Architecture

**Behaviour** (`lib/research_agent/providers/behaviour.ex`)
- Defines consistent interface for all providers
- Two primary operations: `search/2` and `synthesize/3`
- Availability checking for runtime provider selection

**Gemini Provider** (`lib/research_agent/providers/gemini.ex`)
- Fast search and initial queries
- Large context windows for processing multiple sources
- Quick summarization capabilities
- Model: `gemini-2.0-flash-exp`

**Claude Provider** (`lib/research_agent/providers/claude.ex`)
- Deep synthesis and analysis
- High-quality, structured outputs
- Nuanced understanding of complex topics
- Model: `claude-opus-4-5-20251101`

### Cascade Strategy

The application demonstrates intelligent provider selection:

```
Quick Research (Speed-optimized):
  Search: Gemini → Claude (fallback)
  Synthesis: Gemini

Deep Research (Quality-optimized):
  Search: Gemini → Claude (fallback)
  Synthesis: Claude → Gemini (fallback)
```

**Why This Strategy?**

1. **Gemini for Search**: Faster response times, efficient for gathering initial sources
2. **Claude for Synthesis**: Superior at creating well-structured, comprehensive reports
3. **Automatic Fallback**: If preferred provider unavailable, seamlessly use alternative
4. **Cost Efficiency**: Use faster/cheaper models where quality difference is minimal

### Workflow Design

#### Quick Research Workflow

```
┌──────────┐
│  Search  │ (Gemini)
└────┬─────┘
     │
┌────▼─────┐
│  Fetch   │ (Filter by reliability)
└────┬─────┘
     │
┌────▼──────┐
│Synthesize │ (Gemini)
└───────────┘
```

**Use Case**: Fast answers to straightforward questions

#### Deep Research Workflow

```
┌──────────┐
│  Search  │ (Gemini w/ retry)
└────┬─────┘
     │
┌────▼─────┐
│  Fetch   │ (Filter by reliability)
└────┬─────┘
     │
┌────▼──────┐
│Summarize  │ (Extract key points)
└────┬──────┘
     │
┌────▼──────┐
│Synthesize │ (Claude w/ retry)
└───────────┘
```

**Use Case**: Comprehensive research requiring deep analysis

### Jido Actions

All workflow steps are implemented as Jido Actions for composability:

1. **SearchWeb** - Query providers for relevant sources
2. **FetchContent** - Convert search results to Source structs with reliability scoring
3. **Summarize** - Create concise summaries of each source
4. **Synthesize** - Generate final research output from sources

### Source Reliability Scoring

Sources are automatically scored (0.0 - 1.0) based on:

| Factor | Weight | Scoring |
|--------|--------|---------|
| Domain | 50% | .edu/.gov: 0.9, .org: 0.7, .com: 0.5 |
| Content | 40% | >5000 chars: 0.9, >2000: 0.7, >1000: 0.6 |
| Metadata | 10% | Title present: +0.1 |

Sources below `reliability_threshold` (default: 0.6) are filtered out.

### Error Handling

**Retry Strategy**:
- Search steps: 2 attempts with 1s backoff
- Synthesis steps: 2 attempts with 1s backoff
- Search failures use `on_error: :continue` to allow workflow continuation

**Cascade Fallback**:
- If primary provider fails, secondary provider is used
- Metadata tracks which provider actually completed each step

### Output Format

Workflow outputs include:

```elixir
%{
  content: "Synthesized research text...",
  provider: :claude,
  sources: [%Source{}, ...],
  source_count: 8,
  metadata: %{
    search_provider: :gemini,
    synthesis_provider: :claude,
    total_found: 10,
    workflow_type: :deep_research
  }
}
```

## Design Decisions

### Why Cascade Over Parallel?

While parallel execution of multiple providers could provide diverse perspectives, we chose cascade because:

1. **Cost Efficiency**: Only use expensive providers when needed
2. **Speed**: Return results as soon as one provider succeeds
3. **Reliability**: Automatic fallback ensures high availability
4. **Simplicity**: Easier to understand and debug than parallel aggregation

### Why Separate Summarize Step?

The deep research workflow includes an explicit summarization step:

1. **Token Limits**: Prevents exceeding context windows with full content
2. **Quality**: Helps synthesis focus on key points
3. **Performance**: Faster processing of condensed information
4. **Composability**: Summaries can be cached and reused

### Provider Selection Logic

```elixir
# Search: Speed-optimized
search_provider = if Gemini.available?(), do: :gemini, else: :claude

# Synthesis: Quality-optimized
synthesis_provider = if Claude.available?(), do: :claude, else: :gemini
```

This ensures the best available provider for each task type.

## Future Enhancements

Potential additions to demonstrate more Synapse features:

1. **Real Web Search Integration**: Connect to Google Search API, Bing, or DuckDuckGo
2. **Parallel Source Processing**: Use Synapse to fetch multiple sources concurrently
3. **Persistence**: Add workflow state persistence for long-running research
4. **Streaming**: Stream synthesis results as they're generated
5. **Multi-stage Refinement**: Iterative research with human-in-the-loop feedback
6. **Citation Graph**: Build knowledge graphs from source relationships

## Testing Strategy

- **Unit Tests**: Query, Source, and individual action behavior
- **Integration Tests**: Full workflow execution with mocked providers
- **Fixtures**: Reusable test data for sources and search results
- **Mox**: Mock provider interfaces for deterministic testing

## Usage Examples

See [README.md](README.md) for detailed usage examples and API documentation.
