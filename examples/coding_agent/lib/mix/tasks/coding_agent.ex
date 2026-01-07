defmodule Mix.Tasks.CodingAgent do
  @shortdoc "Run a coding task through the multi-model agent"

  @moduledoc """
  Run a coding task through the multi-model agent.

  ## Usage

      mix coding_agent "Write a function to parse JSON"
      mix coding_agent "Review this code" --type review --provider codex
      mix coding_agent "Analyze this algorithm" --parallel

  ## Options

    * `--type` - Task type: generate, review, analyze, refactor, explain, fix
    * `--provider` - Specific provider: claude, codex, gemini
    * `--parallel` - Run with all providers and aggregate results
    * `--cascade` - Try providers in sequence until one succeeds
    * `--context` - Code context to include (as string)
    * `--language` - Programming language hint
    * `--file` - Read context from a file

  ## Examples

      # Simple generation
      mix coding_agent "Write a GenServer for rate limiting"

      # Code review with Codex
      mix coding_agent "Review this code for security issues" --provider codex --file lib/auth.ex

      # Parallel analysis
      mix coding_agent "Analyze this algorithm" --parallel --file lib/sort.ex

      # Cascade for reliability
      mix coding_agent "Fix the failing test" --cascade
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _invalid} =
      OptionParser.parse(args,
        switches: [
          type: :string,
          provider: :string,
          parallel: :boolean,
          cascade: :boolean,
          context: :string,
          language: :string,
          file: :string,
          help: :boolean
        ],
        aliases: [
          t: :type,
          p: :provider,
          c: :context,
          l: :language,
          f: :file,
          h: :help
        ]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else
      run_task(args, opts)
    end
  end

  defp run_task(args, opts) do
    input = Enum.join(args, " ")

    if input == "" do
      Mix.raise("Please provide a task description. Use --help for usage.")
    end

    # Build task options
    task_opts = build_task_opts(opts)

    # Execute based on mode
    result =
      cond do
        opts[:parallel] ->
          CodingAgent.execute_parallel(input, task_opts)

        opts[:cascade] ->
          CodingAgent.execute_cascade(input, task_opts)

        opts[:provider] ->
          provider = String.to_atom(opts[:provider])
          CodingAgent.execute(input, [{:provider, provider} | task_opts])

        true ->
          CodingAgent.execute(input, task_opts)
      end

    handle_result(result)
  end

  defp build_task_opts(opts) do
    task_opts = []

    task_opts =
      if opts[:type] do
        [{:type, String.to_atom(opts[:type])} | task_opts]
      else
        task_opts
      end

    task_opts =
      if opts[:language] do
        [{:language, opts[:language]} | task_opts]
      else
        task_opts
      end

    # Handle context from file or direct
    task_opts =
      cond do
        opts[:file] ->
          context = File.read!(opts[:file])
          [{:context, context} | task_opts]

        opts[:context] ->
          [{:context, opts[:context]} | task_opts]

        true ->
          task_opts
      end

    task_opts
  end

  defp handle_result(result) do
    case result do
      {:ok, %{result: %{content: content}}} ->
        Mix.shell().info("\n#{content}")

      {:ok, %{combined: combined}} ->
        Mix.shell().info("\n#{combined}")

      {:ok, %{content: content}} ->
        Mix.shell().info("\n#{content}")

      {:ok, result} when is_map(result) ->
        content = Map.get(result, :content) || Map.get(result, :combined) || inspect(result)
        Mix.shell().info("\n#{content}")

      {:error, :all_providers_failed} ->
        Mix.raise("All providers failed. Check your API keys and try again.")

      {:error, reason} ->
        Mix.raise("Task failed: #{inspect(reason)}")
    end
  end
end
