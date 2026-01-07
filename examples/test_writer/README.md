# TestWriter

Automated ExUnit test generation for Elixir modules using AI providers and the Synapse workflow framework.

## Overview

TestWriter analyzes your Elixir modules, generates comprehensive ExUnit tests, and validates them automatically. It supports two workflows:

- **Simple Generate**: Fast test generation without validation
- **Validated Generate**: Generation with automatic compilation checking and error fixing

## Features

- 🔍 **Automatic Function Discovery**: Extracts public functions from modules
- 🤖 **AI-Powered Generation**: Uses Codex to generate comprehensive tests
- ✅ **Validation & Fixing**: Automatically compiles and fixes generated tests
- 📊 **Coverage Analysis**: Estimates test coverage based on function names
- 🎯 **Quality Checks**: Validates test structure, assertions, and naming
- 🔄 **Workflow Orchestration**: Powered by Synapse for reliable execution

## Installation

### Prerequisites

- Elixir 1.15 or later
- OpenAI API key (for Codex provider)

### Setup

1. Clone the repository and navigate to the example:

```bash
cd synapse/examples/test_writer
```

2. Install dependencies:

```bash
mix deps.get
```

3. Set your API key:

```bash
export OPENAI_API_KEY="your-api-key-here"
```

Or configure in `config/dev.exs`:

```elixir
config :codex_sdk, api_key: "your-api-key-here"
```

## Usage

### Quick Start

```elixir
# Start IEx with the application
iex -S mix

# Simple generation (fast, no validation)
{:ok, result} = TestWriter.generate_tests(MyModule)
File.write!("test/my_module_test.exs", result.code)

# Validated generation (with compilation checking and fixing)
{:ok, result} = TestWriter.generate_tests(MyModule, validated: true)
File.write!("test/my_module_test.exs", result.code)
```

### Analyze Before Generating

```elixir
# See what functions would be tested
{:ok, functions} = TestWriter.analyze(MyModule)

Enum.each(functions, fn f ->
  IO.puts("#{f.name}/#{f.arity} - #{f.type}")
end)
```

### Advanced Options

```elixir
# With additional context for better test generation
{:ok, result} = TestWriter.generate_tests(
  MyModule,
  validated: true,
  context: "This module handles user authentication with OAuth2",
  max_fix_attempts: 3
)

# Using a Target for more control
target = TestWriter.Target.new(MyModule,
  path: "lib/my_module.ex",
  metadata: %{priority: :high}
)

{:ok, result} = TestWriter.generate_tests(target, validated: true)
```

### Generate and Save

```elixir
# One-step generation and save
{:ok, path} = TestWriter.generate_and_save(
  MyModule,
  "test/my_module_test.exs",
  validated: true
)

IO.puts("Tests saved to: #{path}")
```

## Example Output

Given a simple calculator module:

```elixir
defmodule Calculator do
  def add(a, b), do: a + b
  def subtract(a, b), do: a - b
  def multiply(a, b), do: a * b
  def divide(_a, 0), do: {:error, :division_by_zero}
  def divide(a, b), do: {:ok, a / b}
end
```

TestWriter generates:

```elixir
defmodule CalculatorTest do
  use ExUnit.Case, async: true

  describe "add/2" do
    test "adds two positive numbers" do
      assert Calculator.add(2, 3) == 5
    end

    test "adds negative numbers" do
      assert Calculator.add(-2, -3) == -5
    end

    test "adds zero" do
      assert Calculator.add(5, 0) == 5
    end
  end

  describe "subtract/2" do
    test "subtracts two positive numbers" do
      assert Calculator.subtract(5, 3) == 2
    end

    test "subtracts with negative result" do
      assert Calculator.subtract(3, 5) == -2
    end
  end

  describe "multiply/2" do
    test "multiplies two positive numbers" do
      assert Calculator.multiply(3, 4) == 12
    end

    test "multiplies by zero" do
      assert Calculator.multiply(5, 0) == 0
    end
  end

  describe "divide/2" do
    test "divides two numbers successfully" do
      assert Calculator.divide(10, 2) == {:ok, 5.0}
    end

    test "returns error when dividing by zero" do
      assert Calculator.divide(10, 0) == {:error, :division_by_zero}
    end
  end
end
```

## Workflows

### Simple Generate Workflow

Fast generation without validation:

```
Analyze Module → Generate Tests → Return Code
```

Use when:
- You want quick results
- You'll manually review/fix tests
- The module is simple

### Validated Generate Workflow

Comprehensive workflow with automatic fixing:

```
Analyze Module → Generate Tests → Compile Tests → Fix if Needed → Validate → Return Code
```

Steps:
1. **Analyze**: Extract public functions
2. **Generate**: Create tests using AI provider
3. **Compile**: Check for syntax/compilation errors
4. **Fix**: Automatically fix errors if compilation fails
5. **Validate**: Run quality checks and validate structure

Use when:
- You want guaranteed compilable tests
- You need coverage analysis
- The module is complex

## Configuration

### Application Config

```elixir
# config/config.exs
config :test_writer,
  max_fix_attempts: 3,
  compile_timeout: 30_000,
  test_timeout: 60_000
```

### Environment Variables

```bash
# OpenAI API key for Codex provider
export OPENAI_API_KEY="sk-..."
```

## Testing

Run the test suite:

```bash
mix test
```

Tests include:
- Unit tests for analyzer and compiler
- Workflow structure tests
- Sample modules for integration testing

## Architecture

### Key Components

- **Target**: Represents a module to test
- **Analyzer**: Extracts functions from modules
- **Compiler**: Validates and compiles test code
- **Providers**: AI providers (Codex) for generation
- **Actions**: Workflow steps (Jido Actions)
- **Workflows**: Orchestrated multi-step processes

See [DESIGN.md](DESIGN.md) for detailed architecture decisions.

### Workflow Pattern: Conditional Execution

TestWriter demonstrates conditional workflow execution:

```elixir
# Compile step continues even on error
[id: :compile, action: CompileTests, on_error: :continue]

# Fix step conditionally executes based on compile result
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

## Limitations

1. **Coverage Heuristic**: Coverage calculation is based on function names in test names (not execution-based)
2. **Test Execution**: Generated tests are compiled but not always executed (for safety)
3. **Single Provider**: Currently only supports Codex (extensible to others)
4. **Fix Attempts**: Limited to single fix attempt in current workflow
5. **Private Functions**: Only tests public functions by default

## Troubleshooting

### "Provider unavailable" error

**Cause**: API key not configured

**Solution**: Set `OPENAI_API_KEY` environment variable

### Compilation errors in generated tests

**Cause**: AI generated invalid code

**Solution**: Use `validated: true` option for automatic fixing

### Tests don't cover all functions

**Cause**: Some functions may be filtered (callbacks, internal functions)

**Solution**: Check `TestWriter.analyze/1` to see what would be tested

### Slow generation

**Cause**: API calls take 1-5 seconds

**Solution**: Use simple workflow for faster results (no validation)

## Examples

The repository includes sample modules for testing:

```elixir
# Try generating tests for sample modules
TestWriter.generate_tests(TestWriter.SampleModules.Calculator, validated: true)
TestWriter.generate_tests(TestWriter.SampleModules.StringHelper, validated: true)
TestWriter.generate_tests(TestWriter.SampleModules.ListHelper, validated: true)
```

## Roadmap

- [ ] Support for Claude and Gemini providers
- [ ] Multi-attempt fix loop workflow
- [ ] Parallel provider comparison
- [ ] Incremental test generation (based on git diff)
- [ ] Test quality scoring with LLM
- [ ] Interactive refinement mode
- [ ] Property-based test generation
- [ ] Execution-based coverage analysis

## Contributing

This is an example application demonstrating Synapse workflow patterns. Contributions welcome!

Areas for improvement:
- Additional providers
- Better prompts for test generation
- Enhanced validation strategies
- Real test execution in sandbox
- Performance optimizations

## License

See parent repository license.

## Acknowledgments

Built with:
- [Synapse](https://github.com/agentjido/synapse) - Multi-agent orchestration framework
- [Jido](https://github.com/agentjido/jido) - Action framework
- [Codex SDK](https://github.com/lebrunel/codex_sdk) - OpenAI integration

## Support

For issues or questions:
1. Check [DESIGN.md](DESIGN.md) for architecture details
2. Review test files for usage examples
3. Open an issue in the parent repository

## Quick Reference

```elixir
# Simple generation
TestWriter.generate_tests(MyModule)

# Validated generation
TestWriter.generate_tests(MyModule, validated: true)

# Analyze only
TestWriter.analyze(MyModule)

# Generate and save
TestWriter.generate_and_save(MyModule, "test/my_module_test.exs", validated: true)

# Check provider
TestWriter.provider_available?(:codex)

# With context
TestWriter.generate_tests(MyModule,
  validated: true,
  context: "Module handles user authentication"
)
```
