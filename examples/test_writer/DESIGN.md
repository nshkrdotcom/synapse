# TestWriter Design Document

## Overview

TestWriter is an automated ExUnit test generation system built on the Synapse multi-agent orchestration framework. It demonstrates advanced workflow patterns including conditional execution, validation loops, and automatic error recovery.

## Architecture

### Core Components

#### 1. Domain Models (`lib/test_writer/`)

- **Target** (`target.ex`): Represents a module to generate tests for
  - Contains module name, file path, and function metadata
  - Supports both loaded modules and source code analysis
  - Provides serialization for workflow passing

- **GeneratedTest** (`generated_test.ex`): Represents generated test code with metadata
  - Tracks compilation status, errors, and validation results
  - Includes coverage information and quality metrics
  - State machine: generated → compiled → validated

#### 2. Analysis & Compilation (`lib/test_writer/`)

- **Analyzer** (`analyzer.ex`): Extracts testable functions from modules
  - Uses reflection for loaded modules (`__info__/1`, `Code.fetch_docs/1`)
  - Uses AST parsing for source code (`Code.string_to_quoted/1`)
  - Filters out internal functions, callbacks, and generated code
  - Calculates test coverage based on function names

- **Compiler** (`compiler.ex`): Validates generated test code
  - Compiles code to check for syntax/semantic errors
  - Runs quality checks (structure, assertions, naming)
  - Executes tests in isolation (sandbox approach)
  - Formats errors for LLM-based fixing

#### 3. Providers (`lib/test_writer/providers/`)

- **Behaviour**: Defines interface for test generation providers
  - `generate_tests/2`: Generate initial tests
  - `fix_tests/3`: Fix compilation/runtime errors
  - `available?/0`: Check if provider is configured

- **Codex Provider**: OpenAI-based code generation
  - Uses codex_sdk for structured code generation
  - Specialized prompts for test generation and fixing
  - Extracts code from markdown blocks
  - Tracks usage metrics and raw responses

#### 4. Workflow Actions (`lib/test_writer/actions/`)

All actions implement `Jido.Action` behaviour for use in Synapse workflows:

- **AnalyzeModule**: Extracts functions from target module
- **GenerateTests**: Calls provider to generate test code
- **CompileTests**: Compiles and checks for errors (returns success with error status)
- **ValidateTests**: Runs tests and validates quality
- **FixTests**: Conditionally fixes errors using provider

#### 5. Workflows (`lib/test_writer/workflows/`)

- **SimpleGenerate**: Basic two-step workflow
  1. Analyze module
  2. Generate tests
  - Fast, no validation
  - Suitable for quick prototyping

- **ValidatedGenerate**: Advanced five-step workflow with conditional execution
  1. Analyze module
  2. Generate tests
  3. Compile tests (continue on error)
  4. Fix tests (conditional based on compile result)
  5. Validate tests
  - Ensures working tests
  - Automatic error recovery

## Design Decisions

### 1. Conditional Workflow Execution

**Decision**: Use `on_error: :continue` and conditional params instead of explicit retry loops.

**Rationale**:
- Synapse's declarative workflow model doesn't support explicit loops
- `on_error: :continue` allows workflow to proceed past failures
- Conditional `params` functions check previous step results
- More maintainable than complex control flow

**Example**:
```elixir
# Compile step continues on error
[id: :compile, action: CompileTests, on_error: :continue]

# Fix step conditionally acts based on compile result
[
  id: :fix,
  action: FixTests,
  params: fn env ->
    case env.results.compile.status do
      :error -> %{code: code, fix: true, errors: errors}
      _ -> %{code: code, fix: false}
    end
  end
]
```

### 2. Max Fix Attempts Strategy

**Decision**: Single fix attempt in workflow, not a retry loop.

**Rationale**:
- Multiple LLM fix attempts often don't improve results
- Better to fail fast and let user intervene
- Can use step-level retry for transient provider errors
- Keeps workflow simple and predictable

**Future**: Could implement multi-attempt fixing with a separate recursive workflow.

### 3. Test Validation Approach

**Decision**: Compile + quality checks, not full test execution.

**Rationale**:
- Running tests safely requires sandboxing/isolation
- Compilation errors are most common issue
- Quality checks catch structural problems
- Full execution could have side effects or be slow

**Implementation**:
```elixir
def validate_quality(code) do
  checks = %{
    has_test_module: check_has_test_module(code),
    has_use_exunit: check_has_use_exunit(code),
    has_test_cases: check_has_test_cases(code),
    has_assertions: check_has_assertions(code),
    descriptive_names: check_descriptive_test_names(code)
  }
end
```

### 4. Coverage Calculation

**Decision**: Heuristic-based coverage (function name in test name).

**Rationale**:
- Accurate coverage requires running tests and instrumenting code
- Heuristic is fast and good enough for feedback
- Helps identify obviously missing tests
- Could be enhanced with static analysis

**Limitation**: May miscount if test names don't match function names.

### 5. Provider Abstraction

**Decision**: Behaviour-based provider interface with single Codex implementation.

**Rationale**:
- Allows future providers (Claude, Gemini, local models)
- Consistent interface for workflows
- Easy to mock for testing
- Each provider can optimize its prompts

### 6. Error Handling Philosophy

**Decision**: Return structured errors, don't raise exceptions in workflows.

**Rationale**:
- Synapse captures errors in audit trail
- Structured errors enable automatic fixing
- Easier to test error paths
- Better observability

### 7. Target Flexibility

**Decision**: Support both loaded modules and source code.

**Rationale**:
- Loaded modules: Better for compiled code (has docs, specs)
- Source code: Better for uncompiled files or different projects
- AST parsing: Works for both cases
- Flexibility in usage patterns

## Workflow Patterns Demonstrated

### 1. Conditional Step Execution

Steps that execute differently based on previous results:

```elixir
params: fn env ->
  if env.results.compile.status == :error do
    %{fix: true, errors: env.results.compile.errors}
  else
    %{fix: false}
  end
end
```

### 2. Error Recovery Pattern

Using `on_error: :continue` to allow workflow to proceed:

```elixir
[id: :compile, action: CompileTests, on_error: :continue]
```

### 3. Multi-Source Outputs

Outputs from different steps:

```elixir
outputs: [
  [key: :code, from: :validate, path: [:final_code]],
  [key: :coverage, from: :validate, path: [:coverage]],
  [key: :fixed, from: :fix, path: [:fixed]]
]
```

### 4. Dynamic Parameters

Parameters computed from environment:

```elixir
params: fn env ->
  %{
    functions: env.results.analyze.testable_functions,
    module_name: target.module
  }
end
```

## Testing Strategy

### Unit Tests

- **Analyzer**: Test function extraction, filtering, coverage calculation
- **Compiler**: Test compilation, quality checks, error formatting
- **Actions**: Test individual action logic (mocked providers)
- **Workflows**: Test structure (full integration requires provider)

### Mocking Strategy

- `Mox` for provider behaviour mocking
- Fixtures for sample code and results
- Sample modules for real analysis tests

### What's NOT Tested

- Full workflow execution (requires API keys)
- Actual LLM quality (non-deterministic)
- Real test execution in sandbox

## Performance Considerations

### Bottlenecks

1. **LLM API calls**: 1-5 seconds per generation/fix
2. **Code compilation**: ~100ms for typical test file
3. **AST parsing**: Negligible for most files

### Optimization Opportunities

1. **Caching**: Cache analysis results for same module
2. **Batching**: Generate tests for multiple modules in parallel
3. **Streaming**: Stream LLM responses for faster perceived performance
4. **Local models**: Use local LLMs for faster iteration (lower quality)

## Security Considerations

### Code Execution Safety

**Issue**: Running generated tests could execute arbitrary code.

**Mitigations**:
1. Compile-only validation (don't execute by default)
2. Sandbox test execution (future enhancement)
3. Code review before committing
4. Limit to test-only operations

### API Key Security

**Issue**: LLM providers require API keys.

**Mitigations**:
1. Environment variable configuration
2. Never commit keys to version control
3. Use provider-specific key rotation
4. Monitor API usage

## Future Enhancements

### 1. Multi-Attempt Fix Loop

Implement a recursive workflow for multiple fix attempts:

```elixir
defmodule ValidatedGenerateWithRetry do
  def run(target, opts, attempt \\ 1) do
    case run_once(target, opts) do
      {:ok, result} -> {:ok, result}
      {:error, _} when attempt < max_attempts ->
        run(target, opts, attempt + 1)
      error -> error
    end
  end
end
```

### 2. Parallel Provider Comparison

Generate tests with multiple providers and compare quality:

```elixir
steps = [
  [id: :codex_gen, action: GenerateTests, params: %{provider: :codex}],
  [id: :claude_gen, action: GenerateTests, params: %{provider: :claude}],
  [id: :compare, action: CompareResults, requires: [:codex_gen, :claude_gen]]
]
```

### 3. Incremental Test Generation

Generate tests incrementally as code changes:

```elixir
def generate_for_changes(git_diff) do
  changed_modules = extract_changed_modules(git_diff)
  Enum.map(changed_modules, &generate_tests/1)
end
```

### 4. Test Quality Scoring

Use LLM to score test quality:

```elixir
defmodule ScoreTestQuality do
  def score(test_code) do
    prompt = "Rate this test from 1-10 for coverage, clarity, and edge cases"
    provider.score(test_code, prompt)
  end
end
```

### 5. Interactive Refinement

Allow user to provide feedback and regenerate:

```elixir
def refine(test_code, feedback) do
  provider.fix_tests(test_code, "User feedback: #{feedback}")
end
```

## Comparison to Alternatives

### vs. Property-Based Testing (StreamData)

- TestWriter: Example-based tests, AI-generated
- StreamData: Property-based, exhaustive testing
- **Complement each other**: Use both for best coverage

### vs. Manual Test Writing

- TestWriter: Fast, comprehensive, may need refinement
- Manual: Slow, targeted, high quality
- **Use case**: TestWriter for boilerplate, manual for complex logic

### vs. Test Coverage Tools (Coveralls)

- TestWriter: Generates missing tests
- Coverage tools: Identify untested code
- **Workflow**: Coverage tool → TestWriter → Review

## Lessons Learned

1. **Declarative workflows require different thinking**: No explicit loops, use conditional params
2. **Error recovery is critical**: LLMs aren't perfect, plan for failures
3. **Quality validation is essential**: Don't trust generated code blindly
4. **Prompts matter greatly**: Small changes in prompts drastically affect output
5. **Structured output helps**: Request specific format (markdown code blocks)
6. **Testing is challenging**: Hard to test non-deterministic AI outputs
7. **Fast feedback loops**: Quick validation helps iterate on prompts

## Conclusion

TestWriter demonstrates how to build a robust AI-powered workflow with:
- Conditional execution patterns
- Automatic error recovery
- Structured validation
- Provider abstraction
- Comprehensive testing

The design prioritizes reliability, maintainability, and extensibility while showcasing Synapse's workflow capabilities.
