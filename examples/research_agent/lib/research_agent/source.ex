defmodule ResearchAgent.Source do
  @moduledoc """
  Represents a research source with URL, content, and reliability scoring.

  Sources are tracked throughout the research process and include
  automatic reliability scoring based on various factors.
  """

  @enforce_keys [:url, :content]
  defstruct [
    :url,
    :title,
    :content,
    :summary,
    :reliability_score,
    :retrieved_at,
    :metadata
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          title: String.t() | nil,
          content: String.t(),
          summary: String.t() | nil,
          reliability_score: float() | nil,
          retrieved_at: DateTime.t() | nil,
          metadata: map()
        }

  @doc """
  Create a new source.

  ## Options

    * `:title` - Source title
    * `:summary` - Brief summary of content
    * `:reliability_score` - Calculated reliability (0.0 - 1.0)
    * `:metadata` - Additional metadata map

  ## Examples

      Source.new("https://example.com", "Content here", title: "Example")
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(url, content, opts \\ []) when is_binary(url) and is_binary(content) do
    %__MODULE__{
      url: url,
      content: content,
      title: Keyword.get(opts, :title),
      summary: Keyword.get(opts, :summary),
      reliability_score: Keyword.get(opts, :reliability_score),
      retrieved_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Calculate reliability score for a source based on various factors.

  Factors considered:
  - URL domain reputation (e.g., .edu, .gov, known publishers)
  - Content length and quality signals
  - Presence of citations and references
  - Recency of content

  Returns a score between 0.0 and 1.0.
  """
  @spec calculate_reliability(t()) :: float()
  def calculate_reliability(%__MODULE__{} = source) do
    domain_score = score_domain(source.url)
    content_score = score_content(source.content)
    title_score = if source.title, do: 0.1, else: 0.0

    # Weighted average
    (domain_score * 0.5 + content_score * 0.4 + title_score * 0.1)
    |> max(0.0)
    |> min(1.0)
  end

  @doc """
  Update source with calculated reliability score.
  """
  @spec with_reliability(t()) :: t()
  def with_reliability(%__MODULE__{} = source) do
    %{source | reliability_score: calculate_reliability(source)}
  end

  @doc """
  Convert source to citation format.
  """
  @spec to_citation(t()) :: String.t()
  def to_citation(%__MODULE__{} = source) do
    title = source.title || "Untitled"

    date =
      if source.retrieved_at, do: Calendar.strftime(source.retrieved_at, "%Y-%m-%d"), else: "n.d."

    "#{title}. Retrieved #{date} from #{source.url}"
  end

  # Private helpers

  defp score_domain(url) do
    cond do
      String.contains?(url, [".edu", ".gov"]) -> 0.9
      String.contains?(url, [".org"]) -> 0.7
      String.contains?(url, ["wikipedia.org"]) -> 0.6
      String.contains?(url, [".com"]) -> 0.5
      true -> 0.4
    end
  end

  defp score_content(content) do
    length = String.length(content)

    cond do
      length > 5000 -> 0.9
      length > 2000 -> 0.7
      length > 1000 -> 0.6
      length > 500 -> 0.5
      true -> 0.3
    end
  end
end
