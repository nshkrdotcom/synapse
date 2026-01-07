# DocGenerator Usage Examples

This file contains practical examples of using DocGenerator to document Elixir code.

## Setup

First, set up your API keys:

```bash
export ANTHROPIC_API_KEY=your_claude_key
export OPENAI_API_KEY=your_openai_key
export GEMINI_API_KEY=your_gemini_key
```

Then start an IEx session:

```bash
cd examples/doc_generator
iex -S mix
```

## Example 1: Document a Single Module

Document the `DocGenerator.Analyzer` module using Claude:

```elixir
{:ok, result} = DocGenerator.generate(DocGenerator.Analyzer, provider: :claude)

# View the generated documentation
IO.puts(result.content)

# Check the provider used
result.provider  # => :claude

# View module information
result.module_info
```

## Example 2: Use Different Providers

Try different providers to see their unique approaches:

```elixir
# Claude - Technical and comprehensive
{:ok, claude_result} = DocGenerator.generate(
  DocGenerator.ModuleInfo,
  provider: :claude,
  style: :formal
)

# Codex - Code examples focus
{:ok, codex_result} = DocGenerator.generate(
  DocGenerator.ModuleInfo,
  provider: :codex,
  style: :tutorial
)

# Gemini - Clear explanations
{:ok, gemini_result} = DocGenerator.generate(
  DocGenerator.ModuleInfo,
  provider: :gemini,
  style: :casual
)

# Compare the results
IO.puts("=== CLAUDE ===")
IO.puts(claude_result.content)
IO.puts("\n=== CODEX ===")
IO.puts(codex_result.content)
IO.puts("\n=== GEMINI ===")
IO.puts(gemini_result.content)
```

## Example 3: Parallel Documentation Generation

Generate documentation using all providers simultaneously:

```elixir
{:ok, result} = DocGenerator.generate_parallel(DocGenerator.Project)

# View combined documentation from all providers
IO.puts(result[:"module_DocGenerator.Project"].merged)

# View individual provider contributions
result[:"module_DocGenerator.Project"].individual.claude
result[:"module_DocGenerator.Project"].individual.codex
result[:"module_DocGenerator.Project"].individual.gemini
```

## Example 4: Document Multiple Modules

Document several related modules:

```elixir
modules = [
  DocGenerator.Project,
  DocGenerator.ModuleInfo,
  DocGenerator.Analyzer
]

{:ok, result} = DocGenerator.generate_project(".",
  modules: modules,
  providers: [:claude, :gemini],
  style: :formal
)

# View the generated README
IO.puts(result.readme.content)

# View documentation for each module
Enum.each(modules, fn mod ->
  key = :"module_#{mod}"
  IO.puts("\n=== #{inspect(mod)} ===")
  IO.puts(result[key].merged)
end)
```

## Example 5: Different Documentation Styles

Explore different documentation styles:

```elixir
module = DocGenerator.Outputs.Markdown

# Formal - Professional technical documentation
{:ok, formal} = DocGenerator.generate(module, style: :formal)

# Casual - Friendly, approachable docs
{:ok, casual} = DocGenerator.generate(module, style: :casual)

# Tutorial - Learning-focused with examples
{:ok, tutorial} = DocGenerator.generate(module,
  style: :tutorial,
  include_examples: true
)

# Reference - Concise API reference
{:ok, reference} = DocGenerator.generate(module,
  style: :reference,
  include_examples: false
)
```

## Example 6: Using Test Fixtures

Use the provided test fixtures:

```elixir
alias DocGenerator.Fixtures

# Document the simple fixture module
{:ok, result} = DocGenerator.generate(Fixtures.SimpleModule)
IO.puts(result.content)

# Document the complex fixture with types and callbacks
{:ok, result} = DocGenerator.generate(Fixtures.ComplexModule)
IO.puts(result.content)

# Document a behaviour module
{:ok, result} = DocGenerator.generate(Fixtures.BehaviourModule)
IO.puts(result.content)
```

## Example 7: Format Documentation Output

Use the output formatters to customize the presentation:

```elixir
alias DocGenerator.{Analyzer, Outputs}

# Analyze a module
{:ok, module_info} = Analyzer.analyze_module(DocGenerator)

# Generate documentation
{:ok, result} = DocGenerator.generate(DocGenerator, provider: :claude)

# Format as Markdown
markdown = Outputs.Markdown.format_module_doc(
  module_info,
  result.content,
  include_header: true,
  include_toc: true
)

IO.puts(markdown)

# Format as ExDoc-compatible
exdoc = Outputs.ExDoc.format_moduledoc(module_info, result.content)
IO.puts(exdoc)
```

## Example 8: Check Provider Availability

Before running, check which providers are configured:

```elixir
# List all available providers
available = DocGenerator.available_providers()
IO.inspect(available)  # => [:claude, :codex] (if those keys are set)

# Check specific provider
if DocGenerator.provider_available?(:claude) do
  {:ok, result} = DocGenerator.generate(MyModule, provider: :claude)
else
  IO.puts("Claude not available, using default")
  {:ok, result} = DocGenerator.generate(MyModule)
end
```

## Example 9: Analyze Code Structure

Explore what the analyzer extracts:

```elixir
alias DocGenerator.Analyzer

# Analyze a module
{:ok, info} = Analyzer.analyze_module(DocGenerator.Workflows.SingleModule)

# Inspect the extracted information
IO.inspect(info.module)           # Module name
IO.inspect(info.moduledoc)        # Existing @moduledoc
IO.inspect(info.functions)        # List of functions
IO.inspect(info.types)            # Custom types
IO.inspect(info.callbacks)        # Callbacks if behaviour
IO.inspect(info.behaviours)       # Implemented behaviours

# Check specific function details
info.functions
|> Enum.find(&(&1.name == :run))
|> IO.inspect()
```

## Example 10: Error Handling

Handle potential errors gracefully:

```elixir
case DocGenerator.generate(NonExistent.Module) do
  {:ok, result} ->
    IO.puts("Success: #{result.content}")

  {:error, {:module_not_loaded, module}} ->
    IO.puts("Module #{inspect(module)} not found or not loaded")

  {:error, {:provider_unavailable, provider}} ->
    IO.puts("Provider #{provider} not available. Check API key.")

  {:error, failure} ->
    IO.puts("Error: #{inspect(failure)}")
end
```

## Example 11: Workflow Introspection

Examine the workflow execution:

```elixir
# The workflows return detailed audit trails
{:ok, result} = DocGenerator.generate(DocGenerator.Project)

# Workflows are powered by Synapse engine which provides audit trails
# Access via the lower-level workflow modules for more control:

alias DocGenerator.Workflows.SingleModule

{:ok, outputs} = SingleModule.run(DocGenerator.Project,
  provider: :claude,
  style: :formal
)

# The result contains outputs from the workflow
IO.inspect(outputs.content)
IO.inspect(outputs.module_info)
```

## Tips

1. **Start Simple**: Use `generate/2` with a single provider before trying parallel execution
2. **Compare Providers**: Each provider has different strengths - try them all to see which fits your needs
3. **Use Fixtures**: The test fixtures provide good examples to experiment with
4. **Check Availability**: Always check provider availability before attempting generation
5. **Handle Errors**: API calls can fail - wrap in try/catch or case statements
6. **Experiment with Styles**: Different styles produce very different documentation
7. **Review Output**: AI-generated docs should always be reviewed before publishing

## Common Patterns

### Document a New Module

```elixir
defmodule MyApp.NewModule do
  def hello, do: "world"
end

# Compile it
Code.compile_quoted(quote do: defmodule MyApp.NewModule do
  def hello, do: "world"
end)

# Document it
{:ok, doc} = DocGenerator.generate(MyApp.NewModule)
IO.puts(doc.content)
```

### Batch Document Multiple Modules

```elixir
modules = [
  MyApp.User,
  MyApp.Post,
  MyApp.Comment
]

results =
  modules
  |> Task.async_stream(
    fn mod -> DocGenerator.generate(mod, provider: :claude) end,
    timeout: 30_000
  )
  |> Enum.map(fn {:ok, result} -> result end)

Enum.each(results, fn {:ok, doc} ->
  IO.puts("\n=== #{doc.module_info.module} ===")
  IO.puts(doc.content)
end)
```
