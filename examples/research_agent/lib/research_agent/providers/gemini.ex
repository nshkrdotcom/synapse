defmodule ResearchAgent.Providers.Gemini do
  @moduledoc """
  Gemini provider adapter for fast research queries.

  Gemini excels at:
  - Quick web searches and information extraction
  - Rapid summarization of gathered content
  - Fast initial research passes
  - Large context window for processing multiple sources
  """

  @behaviour ResearchAgent.Providers.Behaviour

  alias ResearchAgent.Query

  @impl true
  def name, do: :gemini

  @impl true
  def available? do
    System.get_env("GEMINI_API_KEY") != nil
  end

  @impl true
  def search(%Query{} = query, opts \\ []) do
    # In a real implementation, this would use Gemini's search capabilities
    # or integrate with a search API. For this example, we'll simulate it.
    prompt = build_search_prompt(query)
    model = Keyword.get(opts, :model, "gemini-2.0-flash-exp")

    try do
      case Gemini.text(prompt, model: model, temperature: 0.3) do
        {:ok, text} ->
          # Parse the response into search results
          results = parse_search_results(text, query.max_sources)

          {:ok,
           %{
             query: query.topic,
             results: results,
             provider: :gemini,
             metadata: %{model: model}
           }}

        {:error, %Gemini.Error{} = error} ->
          {:error, {:gemini_error, error.message}}

        {:error, reason} ->
          {:error, {:gemini_error, reason}}
      end
    rescue
      e -> {:error, {:gemini_exception, Exception.message(e)}}
    end
  end

  @impl true
  def synthesize(sources, %Query{} = query, opts \\ []) do
    prompt = build_synthesis_prompt(sources, query)
    model = Keyword.get(opts, :model, "gemini-2.0-flash-exp")

    try do
      case Gemini.text(prompt,
             model: model,
             temperature: 0.4,
             max_output_tokens: 8192
           ) do
        {:ok, text} ->
          {:ok,
           %{
             content: text,
             provider: :gemini,
             model: model,
             sources_cited: extract_urls(sources),
             metadata: %{source_count: length(sources)}
           }}

        {:error, %Gemini.Error{} = error} ->
          {:error, {:gemini_error, error.message}}

        {:error, reason} ->
          {:error, {:gemini_error, reason}}
      end
    rescue
      e -> {:error, {:gemini_exception, Exception.message(e)}}
    end
  end

  # Private helpers

  defp build_search_prompt(query) do
    """
    You are a research assistant helping to find reliable sources.

    Topic: #{query.topic}

    Generate a list of #{query.max_sources} simulated search results for this topic.
    For each result, provide:
    - A realistic URL (use actual domains like .edu, .org, .gov, Wikipedia, etc.)
    - A clear title
    - A brief snippet (2-3 sentences)

    Format each result as:
    URL: [url]
    Title: [title]
    Snippet: [snippet]

    ---

    Focus on authoritative, reliable sources.
    """
  end

  defp build_synthesis_prompt(sources, query) do
    sources_text =
      sources
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {source, idx} ->
        """
        Source #{idx}:
        URL: #{source.url}
        Title: #{source.title || "Untitled"}
        Content: #{String.slice(source.content || source.snippet || "", 0, 1000)}
        """
      end)

    """
    You are a research assistant synthesizing information from multiple sources.

    Research Topic: #{query.topic}

    Sources:
    #{sources_text}

    Please create a comprehensive, well-structured research summary that:
    1. Synthesizes the key information from all sources
    2. Organizes the content logically with clear sections
    3. #{if query.include_citations, do: "Includes citations [1], [2], etc. referring to the source numbers", else: "Does not include citations"}
    4. Highlights important findings and insights
    5. Maintains objectivity and accuracy

    Provide a clear, informative summary suitable for academic or professional use.
    """
  end

  defp parse_search_results(text, max_sources) do
    # Simple parsing logic - in production, you'd want more robust parsing
    text
    |> String.split("---")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.take(max_sources)
    |> Enum.map(&parse_single_result/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp parse_single_result(text) do
    with url when not is_nil(url) <- extract_field(text, "URL"),
         title when not is_nil(title) <- extract_field(text, "Title"),
         snippet when not is_nil(snippet) <- extract_field(text, "Snippet") do
      %{url: url, title: title, snippet: snippet}
    else
      _ -> nil
    end
  end

  defp extract_field(text, field_name) do
    case Regex.run(~r/#{field_name}:\s*(.+?)(?:\n|$)/s, text) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp extract_urls(sources) do
    Enum.map(sources, fn source ->
      source[:url] || source.url || ""
    end)
    |> Enum.filter(&(&1 != ""))
  end
end
