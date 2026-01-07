defmodule DocGenerator do
  @moduledoc """
  Multi-provider documentation generator for Elixir projects.

  DocGenerator orchestrates Claude, Codex, and Gemini to create comprehensive
  documentation for Elixir codebases. It analyzes module structure, generates
  documentation using multiple AI providers, and produces output in various formats.

  ## Features

  - **Parallel Workflow**: Generate docs with multiple providers simultaneously
  - **Code Analysis**: Extract functions, types, specs, and callbacks
  - **Multi-format Output**: Markdown, ExDoc, README, and guides
  - **Style Customization**: Formal, casual, tutorial, or reference styles

  ## Usage

  ### Generate documentation for a single module

      {:ok, result} = DocGenerator.generate(MyModule, provider: :claude)

  ### Generate with multiple providers in parallel

      {:ok, result} = DocGenerator.generate_parallel(MyModule)

  ### Generate documentation for an entire project

      {:ok, result} = DocGenerator.generate_project("/path/to/project")

  ### Generate with specific style

      {:ok, result} = DocGenerator.generate(MyModule,
        provider: :gemini,
        style: :tutorial,
        include_examples: true
      )

  ## Providers

  - **Claude** - Technical accuracy and comprehensive explanations
  - **Codex** - Code examples and usage patterns
  - **Gemini** - Clear, accessible explanations

  ## Styles

  - `:formal` - Professional, technical documentation
  - `:casual` - Approachable, friendly documentation
  - `:tutorial` - Step-by-step learning focused
  - `:reference` - Concise API reference style
  """

  alias DocGenerator.Workflows.{SingleModule, FullProject}

  @type doc_style :: :formal | :casual | :tutorial | :reference
  @type provider :: :claude | :codex | :gemini

  @doc """
  Generate documentation for a single module.

  ## Options

    * `:provider` - Provider to use (:claude, :codex, :gemini). Default: :claude
    * `:style` - Documentation style. Default: :formal
    * `:include_examples` - Include code examples. Default: true

  ## Examples

      {:ok, result} = DocGenerator.generate(MyApp.User)
      {:ok, result} = DocGenerator.generate(MyApp.User, provider: :codex, style: :tutorial)
  """
  @spec generate(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(module, opts \\ []) when is_atom(module) do
    SingleModule.run(module, opts)
  end

  @doc """
  Generate documentation for a module using multiple providers in parallel.

  Results from all providers are aggregated and returned together.

  ## Options

    * `:providers` - List of providers. Default: [:claude, :codex, :gemini]
    * `:style` - Documentation style. Default: :formal
    * `:include_examples` - Include code examples. Default: true

  ## Examples

      {:ok, result} = DocGenerator.generate_parallel(MyApp.User)
      {:ok, result} = DocGenerator.generate_parallel(MyApp.User, providers: [:claude, :gemini])
  """
  @spec generate_parallel(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_parallel(module, opts \\ []) when is_atom(module) do
    providers = Keyword.get(opts, :providers, [:claude, :codex, :gemini])
    FullProject.run_parallel(".", [module], Keyword.put(opts, :providers, providers))
  end

  @doc """
  Generate documentation for an entire project.

  Discovers modules in the project and generates documentation for each.

  ## Options

    * `:modules` - Specific modules to document. Default: all discovered
    * `:providers` - Providers to use. Default: [:claude, :codex, :gemini]
    * `:style` - Documentation style. Default: :formal
    * `:include_examples` - Include code examples. Default: true
    * `:parallel` - Use parallel execution. Default: true

  ## Examples

      {:ok, result} = DocGenerator.generate_project("/path/to/project")
      {:ok, result} = DocGenerator.generate_project(".", modules: [MyApp.User, MyApp.Post])
  """
  @spec generate_project(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_project(path, opts \\ []) when is_binary(path) do
    modules = Keyword.get(opts, :modules, [])

    if Keyword.get(opts, :parallel, true) and modules != [] do
      FullProject.run_parallel(path, modules, opts)
    else
      FullProject.run(path, opts)
    end
  end

  @doc """
  Check which providers are currently available.

  Returns a list of provider atoms that have valid API credentials configured.

  ## Examples

      DocGenerator.available_providers()
      # => [:claude, :codex]
  """
  @spec available_providers() :: [provider()]
  def available_providers do
    [:claude, :codex, :gemini]
    |> Enum.filter(&provider_available?/1)
  end

  @doc """
  Check if a specific provider is available.

  ## Examples

      DocGenerator.provider_available?(:claude)
      # => true
  """
  @spec provider_available?(provider()) :: boolean()
  def provider_available?(provider) do
    case provider do
      :claude -> Application.get_env(:doc_generator, :claude_available, false)
      :codex -> Application.get_env(:doc_generator, :codex_available, false)
      :gemini -> Application.get_env(:doc_generator, :gemini_available, false)
      _ -> false
    end
  end

  @doc """
  Get the default documentation style.

  ## Examples

      DocGenerator.default_style()
      # => :formal
  """
  @spec default_style() :: doc_style()
  def default_style do
    Application.get_env(:doc_generator, :default_style, :formal)
  end
end
