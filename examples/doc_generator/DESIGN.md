# DocGenerator Design Document

## Overview

DocGenerator is an example application demonstrating Synapse's workflow orchestration capabilities for multi-provider AI coordination. It generates documentation for Elixir projects by analyzing code structure and leveraging multiple AI providers in parallel.

## Architecture Goals

1. **Demonstrate Parallel Workflows**: Show how Synapse executes independent tasks concurrently
2. **Provider Abstraction**: Implement a clean interface for multiple AI providers
3. **Code Introspection**: Leverage Elixir's metaprogramming for analysis
4. **Practical Example**: Create a genuinely useful tool, not just a toy demo

## Core Components

### 1. Code Analysis Layer

**Module**: `DocGenerator.Analyzer`

Uses Elixir's built-in introspection capabilities:

- `Code.fetch_docs/1` - Extract existing documentation
- `Module.__info__/1` - Get function lists
- `Code.Typespec.fetch_types/1` - Extract type definitions
- `Code.Typespec.fetch_callbacks/1` - Extract callback specs

**Design Decision**: Use native Elixir introspection rather than parsing source files. This is more reliable and works with compiled modules, but requires modules to be loaded first.

**Trade-off**: Cannot analyze uncompiled code, but gains simplicity and accuracy.

### 2. Provider Layer

**Modules**: `DocGenerator.Providers.*`

Each provider implements the `DocGenerator.Providers.Behaviour`:

```elixir
@callback generate_module_doc(ModuleInfo.t(), generation_opts()) ::
  {:ok, result()} | {:error, term()}
```

**Provider Specializations**:

- **Claude**: Technical accuracy, comprehensive explanations
  - Best for: API documentation, complex systems
  - Prompt strategy: Emphasize precision and completeness

- **Codex**: Code examples, practical usage
  - Best for: Tutorials, getting started guides
  - Prompt strategy: Request concrete examples

- **Gemini**: Clear explanations, accessibility
  - Best for: User-facing docs, conceptual overviews
  - Prompt strategy: Focus on clarity and simplicity

**Design Decision**: Each provider has its own module rather than a generic adapter. This allows provider-specific optimizations and prompt engineering.

### 3. Workflow Layer

**Modules**: `DocGenerator.Workflows.*`

Implements two main patterns:

#### SingleModule Workflow

Simple sequential workflow:
1. Analyze module structure
2. Generate documentation with one provider

**Use Case**: Quick documentation for a single module, or when you want output from a specific provider.

#### FullProject Workflow (Parallel)

Complex parallel workflow inspired by `CodingAgent.Workflows.ParallelReview`:

```
┌─────────────────┐
│ Analyze Project │
└────────┬────────┘
         │
    ┌────┴──────────────────────────┐
    │                               │
┌───▼────────┐  ┌─────────┐  ┌────▼─────┐
│ Module A   │  │ ...     │  │ Module N │
│  Claude    │  │         │  │  Claude  │
│  Codex     │  │         │  │  Codex   │
│  Gemini    │  │         │  │  Gemini  │
└───┬────────┘  └─────────┘  └────┬─────┘
    │                             │
┌───▼────────┐              ┌────▼─────┐
│ Aggregate  │              │ Aggregate│
│ Module A   │              │ Module N │
└───┬────────┘              └────┬─────┘
    │                             │
    └────────┬────────────────────┘
             │
      ┌──────▼──────┐
      │ Generate    │
      │ README      │
      └─────────────┘
```

**Key Features**:

1. **Parallel Provider Execution**: All providers run simultaneously per module
2. **Error Tolerance**: `on_error: :continue` allows partial failures
3. **Aggregation**: Results from multiple providers are merged
4. **Dependency Management**: Synapse handles execution order automatically

**Design Decision**: Generate docs for each module with all providers in parallel, then aggregate. This maximizes throughput and allows comparison between provider outputs.

**Alternative Considered**: Sequential per-provider execution (all modules with Claude, then all with Codex, etc.). Rejected because it doesn't leverage parallelism as effectively.

### 4. Aggregation Strategy

**Module**: `DocGenerator.Actions.AggregateDocs`

Three strategies for merging provider outputs:

1. **Combine** (default): Concatenate all provider results with headers
   - Pro: Preserves all information
   - Con: Can be lengthy

2. **Best**: Select the longest/most comprehensive output
   - Pro: Concise
   - Con: Discards potentially useful information

3. **Consensus**: Synthesize a merged version (future: use AI)
   - Pro: Best of all worlds
   - Con: Complex, requires additional API calls

**Design Decision**: Default to "combine" strategy for transparency. Users can see what each provider contributed.

**Future Enhancement**: Implement true consensus using an additional AI call to synthesize the best documentation from all providers.

### 5. Output Formatting

**Modules**: `DocGenerator.Outputs.*`

Two main formatters:

- **Markdown**: General-purpose markdown for README, guides
- **ExDoc**: Elixir-specific format for `@moduledoc`, `@doc` attributes

**Design Decision**: Separate formatters rather than one generic formatter. Each format has specific requirements (e.g., ExDoc needs proper escaping for string literals).

## Workflow Execution Flow

### Single Module Documentation

```elixir
DocGenerator.generate(MyModule, provider: :claude)
```

1. `Spec.new` creates workflow specification
2. `Engine.execute` runs the workflow:
   - **Step 1**: `AnalyzeModule` action
     - Introspects module
     - Extracts functions, types, callbacks
     - Returns `ModuleInfo` struct
   - **Step 2**: `GenerateModuleDoc` action (requires Step 1)
     - Receives `ModuleInfo` from step 1
     - Calls Claude provider
     - Returns generated documentation
3. Engine collects outputs and returns result

### Parallel Project Documentation

```elixir
DocGenerator.generate_project(".", modules: [A, B], providers: [:claude, :codex])
```

1. Build dynamic workflow:
   - Create `GenerateModuleDoc` step for each (module, provider) pair
   - For 2 modules × 2 providers = 4 parallel generation steps
   - Create 2 aggregation steps (one per module)
   - Create 1 README generation step

2. Execute workflow:
   - All 4 generation steps run in parallel
   - Aggregation steps wait for their dependencies
   - README generation waits for all aggregations

3. Return comprehensive results with per-module and project-level docs

## Elixir Introspection Approach

### Why Code.fetch_docs/1?

Elixir's documentation is stored in compiled bytecode. `Code.fetch_docs/1` provides structured access:

```elixir
{:docs_v1, anno, beam_language, format, module_doc, metadata, docs}
```

This gives us:
- Module-level documentation
- Function-level docs with signatures
- Type and callback documentation
- Original source metadata

**Advantage**: Works with any compiled module, including dependencies.

**Limitation**: Requires module to be compiled and loaded.

### Function Discovery

Two approaches used:

1. `Module.__info__(:functions)` - Lists all public functions
2. `Code.fetch_docs/1` - Provides documentation for each function

**Design Decision**: Use both. `__info__` for the list, `fetch_docs` for details.

### Type and Spec Extraction

Uses `Code.Typespec` module:

```elixir
{:ok, types} = Code.Typespec.fetch_types(module)
{:ok, specs} = Code.Typespec.fetch_specs(module)
{:ok, callbacks} = Code.Typespec.fetch_callbacks(module)
```

**Design Decision**: Extract specs separately from docs to ensure we capture all type information, even if not documented.

## Error Handling Strategy

### Provider-Level

Each provider action includes:

```elixir
on_error: :continue
retry: [max_attempts: 2, backoff: 500]
```

**Rationale**: Documentation generation should be fault-tolerant. If Claude fails, we still want Codex and Gemini results.

### Workflow-Level

Aggregation handles missing results gracefully:

```elixir
{successful, failed} = Enum.split_with(results, &successful?/1)
```

**Design Decision**: Return partial results rather than failing entirely. Better to have documentation from 2/3 providers than none.

### Module Analysis

Analysis failures halt the workflow for that module:

```elixir
on_error: :halt  # (default)
```

**Rationale**: Can't generate documentation without module metadata. Fail fast and clearly.

## Performance Considerations

### Parallel Execution

For N modules with P providers:
- **Sequential**: N × P × T (where T = average provider time)
- **Parallel**: N × T + aggregation time

**Example**: 10 modules, 3 providers, 5s per call
- Sequential: 150 seconds
- Parallel: ~15 seconds (3× speedup)

### API Rate Limits

**Consideration**: Parallel execution may hit rate limits.

**Mitigation Strategies**:
1. Batch size limits (process modules in groups)
2. Provider-level rate limiting (future)
3. Exponential backoff on 429 errors

**Current Implementation**: No built-in rate limiting. Users should handle via environment configuration.

## Output File Structure

Generated documentation can be written to:

```
docs/
├── modules/
│   ├── MyApp.User.md
│   ├── MyApp.Post.md
│   └── ...
├── README.md
└── guides/
    ├── getting_started.md
    └── api_reference.md
```

**Design Decision**: Keep generation and writing separate. DocGenerator returns strings; users decide where to write them.

**Future Enhancement**: Add file-writing actions to the workflow for complete automation.

## Testing Approach

### Unit Tests

Test individual components without API calls:

- `AnalyzerTest`: Uses real fixture modules
- `ModuleInfoTest`: Tests data structures
- `OutputsTest`: Tests formatters with sample data

### Integration Tests

**Challenge**: Require API credentials.

**Solution**: Use `@tag :skip` for tests needing real providers.

**Alternative**: Mock providers using Mox (partially implemented in test_helper.exs).

### Fixtures

`DocGenerator.Fixtures` provides:
- Sample modules with various characteristics
- Mock provider responses
- Test project structures

**Design Decision**: Use real Elixir modules as fixtures rather than synthetic data. This ensures analysis code works with real introspection.

## Extensibility Points

### Adding New Providers

1. Create module in `lib/doc_generator/providers/`
2. Implement `DocGenerator.Providers.Behaviour`
3. Add to config for availability checking
4. Add to default provider list in workflows

### Custom Aggregation Strategies

Implement new merge logic in `AggregateDocs.merge_content/2`:

```elixir
defp merge_content(provider_docs, :custom_strategy) do
  # Your logic here
end
```

### New Output Formats

Create module in `lib/doc_generator/outputs/`:

```elixir
defmodule DocGenerator.Outputs.HTML do
  def format_module_doc(module_info, content, opts) do
    # Generate HTML
  end
end
```

### Custom Workflows

Extend `Workflows` module with new patterns:

```elixir
defmodule DocGenerator.Workflows.Incremental do
  # Only document changed modules
end
```

## Comparison to CodingAgent

Both examples demonstrate Synapse workflows but with different focuses:

| Aspect | CodingAgent | DocGenerator |
|--------|-------------|--------------|
| **Input** | Natural language tasks | Elixir modules |
| **Analysis** | Task classification | Code introspection |
| **Providers** | General-purpose | Documentation-specialized |
| **Output** | Code/explanations | Structured documentation |
| **Workflows** | SingleProvider, ParallelReview, Cascade | SingleModule, FullProject |
| **Error Handling** | Task-specific | Module-specific |

**Key Similarity**: Both use the ParallelReview pattern for multi-provider execution.

**Key Difference**: DocGenerator does structural analysis first, CodingAgent routes based on intent.

## Future Enhancements

### 1. Incremental Documentation

Only re-document modules that have changed since last run.

**Implementation**:
- Track module hash/modification time
- Skip analysis for unchanged modules
- Merge old and new documentation

### 2. Documentation Quality Scoring

Evaluate generated docs for completeness, clarity, accuracy.

**Implementation**:
- Add scoring action to workflow
- Use separate AI provider to score docs
- Include scores in output metadata

### 3. Interactive Refinement

Allow users to request clarifications or improvements.

**Implementation**:
- Multi-turn conversation per module
- Track refinement history
- Allow provider switching mid-refinement

### 4. Custom Templates

User-defined templates for documentation structure.

**Implementation**:
- Template DSL or Markdown files
- Variable substitution
- Provider instructions based on template

### 5. Documentation Validation

Check that docs match code reality.

**Implementation**:
- Parse doc examples
- Run examples against actual code
- Report inconsistencies

## Lessons Learned

### 1. Provider-Specific Prompting Matters

Generic prompts produce generic docs. Tailoring prompts to each provider's strengths yields better results.

### 2. Introspection is Powerful

Elixir's built-in introspection eliminates the need for AST parsing or source file analysis.

### 3. Parallel Workflows Scale Well

The ParallelReview pattern naturally scales with the number of modules and providers.

### 4. Error Tolerance is Critical

With multiple providers, some failures are inevitable. Graceful degradation is essential.

### 5. Aggregation is Non-Trivial

Simply concatenating provider outputs works but isn't optimal. Smart synthesis would add significant value.

## Conclusion

DocGenerator demonstrates how Synapse's workflow engine can orchestrate complex, multi-step AI operations with parallel execution, error handling, and flexible configuration. The code analysis and documentation generation domain provides a practical example of Synapse's capabilities while producing a genuinely useful tool.
