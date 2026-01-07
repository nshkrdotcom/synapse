defmodule ResearchAgent.Providers.Claude do
  @moduledoc """
  Claude provider adapter for deep synthesis and analysis.

  Claude excels at:
  - Deep, thoughtful synthesis of complex information
  - Nuanced analysis and critical evaluation
  - High-quality, well-structured research outputs
  - Comprehensive coverage of multifaceted topics
  """

  @behaviour ResearchAgent.Providers.Behaviour

  alias ResearchAgent.Query

  @impl true
  def name, do: :claude

  @impl true
  def available? do
    # Claude Agent SDK can use CLI auth or API key
    System.get_env("ANTHROPIC_API_KEY") != nil or
      File.exists?(Path.expand("~/.anthropic/auth_token"))
  end

  @impl true
  def search(%Query{} = query, _opts \\ []) do
    # Claude doesn't have native search, so we use it to formulate search queries
    # In a real implementation, this would integrate with a search API
    # For this example, we simulate search results
    results = simulate_search_results(query)

    {:ok,
     %{
       query: query.topic,
       results: results,
       provider: :claude,
       metadata: %{simulated: true}
     }}
  end

  @impl true
  def synthesize(sources, %Query{} = query, opts \\ []) do
    prompt = build_synthesis_prompt(sources, query)
    model = Keyword.get(opts, :model, "claude-opus-4-5-20251101")

    try do
      case ClaudeAgentSDK.text(prompt,
             model: model,
             temperature: 0.4,
             max_tokens: 16384
           ) do
        {:ok, response} ->
          content = extract_text_content(response)

          {:ok,
           %{
             content: content,
             provider: :claude,
             model: model,
             sources_cited: extract_urls(sources),
             metadata: %{
               source_count: length(sources),
               usage: response[:usage]
             }
           }}

        {:error, error} ->
          {:error, {:claude_error, format_error(error)}}
      end
    rescue
      e -> {:error, {:claude_exception, Exception.message(e)}}
    end
  end

  # Private helpers

  defp simulate_search_results(query) do
    # Simulated search results for testing
    Enum.map(1..query.max_sources, fn i ->
      %{
        url: "https://example#{i}.edu/research/#{slugify(query.topic)}",
        title: "#{query.topic} - Resource #{i}",
        snippet: "Authoritative information about #{query.topic} from source #{i}."
      }
    end)
  end

  defp build_synthesis_prompt(sources, query) do
    sources_text =
      sources
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {source, idx} ->
        content = source[:content] || source.content || source[:snippet] || source.snippet || ""

        """
        Source #{idx}:
        URL: #{source[:url] || source.url}
        Title: #{source[:title] || source.title || "Untitled"}
        Content: #{String.slice(content, 0, 2000)}
        """
      end)

    citation_instruction =
      if query.include_citations do
        "Use [1], [2], etc. to cite sources throughout your synthesis."
      else
        ""
      end

    """
    You are an expert research analyst tasked with synthesizing information from multiple sources into a comprehensive, well-structured report.

    Research Topic: #{query.topic}

    Sources:
    #{sources_text}

    Please create a thorough research synthesis that:

    1. **Introduction**: Provide context and overview of the topic
    2. **Main Findings**: Synthesize the key information from all sources, organized into logical sections
    3. **Analysis**: Offer insights, connections, and critical evaluation
    4. **Conclusion**: Summarize the most important takeaways
    5. **Sources**: #{if query.include_citations, do: "List all sources referenced", else: "Brief mention of source types"}

    #{citation_instruction}

    Aim for depth, clarity, and academic rigor. The output should be suitable for professional or scholarly use.
    """
  end

  defp extract_text_content(response) when is_map(response) do
    cond do
      is_binary(response[:content]) ->
        response[:content]

      is_list(response[:content]) ->
        Enum.map_join(response[:content], "\n", &extract_block_text/1)

      is_binary(response["content"]) ->
        response["content"]

      true ->
        inspect(response)
    end
  end

  defp extract_text_content(response) when is_binary(response), do: response
  defp extract_text_content(_), do: ""

  defp extract_block_text(%{text: text}), do: text
  defp extract_block_text(%{"text" => text}), do: text
  defp extract_block_text(%{type: "text", text: text}), do: text
  defp extract_block_text(%{"type" => "text", "text" => text}), do: text
  defp extract_block_text(_), do: ""

  defp format_error(%{message: message}), do: message
  defp format_error(%{"message" => message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp extract_urls(sources) do
    Enum.map(sources, fn source ->
      source[:url] || (is_map(source) && Map.get(source, :url)) || ""
    end)
    |> Enum.filter(&(&1 != ""))
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
