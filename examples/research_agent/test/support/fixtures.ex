defmodule ResearchAgent.Fixtures do
  @moduledoc """
  Test fixtures for research agent.
  """

  alias ResearchAgent.{Query, Source}

  def query_fixture(attrs \\ %{}) do
    topic = attrs[:topic] || "Test research topic"

    Query.new(topic,
      depth: attrs[:depth] || :quick,
      max_sources: attrs[:max_sources] || 5,
      reliability_threshold: attrs[:reliability_threshold] || 0.6,
      include_citations: attrs[:include_citations] || true
    )
  end

  def source_fixture(attrs \\ %{}) do
    url = attrs[:url] || "https://example.edu/research"
    content = attrs[:content] || "Sample research content about the topic."

    Source.new(url, content,
      title: attrs[:title] || "Sample Research Article",
      reliability_score: attrs[:reliability_score]
    )
  end

  def search_results_fixture(count \\ 3) do
    %{
      query: "test query",
      results:
        Enum.map(1..count, fn i ->
          %{
            url: "https://example#{i}.edu/research",
            title: "Research Article #{i}",
            snippet: "This is a sample research snippet about the topic from source #{i}."
          }
        end),
      provider: :gemini,
      metadata: %{model: "gemini-2.0-flash-exp"}
    }
  end

  def synthesis_result_fixture(attrs \\ %{}) do
    %{
      content: attrs[:content] || "Comprehensive research synthesis with multiple sections.",
      provider: attrs[:provider] || :claude,
      model: attrs[:model] || "claude-opus-4-5-20251101",
      sources_cited: attrs[:sources_cited] || ["https://example1.edu", "https://example2.edu"],
      metadata: attrs[:metadata] || %{source_count: 3}
    }
  end
end
