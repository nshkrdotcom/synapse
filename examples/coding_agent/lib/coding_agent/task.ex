defmodule CodingAgent.Task do
  @moduledoc """
  Represents a coding task with input, type classification, and metadata.

  Tasks are automatically classified based on keywords in the input,
  or can be explicitly typed via options.
  """

  @enforce_keys [:id, :input, :type]
  defstruct [
    :id,
    :input,
    :type,
    :context,
    :language,
    :files,
    :metadata,
    :inserted_at
  ]

  @type task_type :: :generate | :review | :analyze | :refactor | :explain | :fix
  @type t :: %__MODULE__{
          id: String.t(),
          input: String.t(),
          type: task_type(),
          context: String.t() | nil,
          language: String.t() | nil,
          files: [String.t()] | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  @doc """
  Create a new task from input string and options.

  ## Options

    * `:type` - Explicit task type, overrides inference
    * `:context` - Code context to include
    * `:language` - Programming language hint
    * `:files` - List of relevant file paths
    * `:metadata` - Additional metadata map
  """
  @spec new(String.t(), keyword()) :: t()
  def new(input, opts \\ []) when is_binary(input) do
    %__MODULE__{
      id: generate_id(),
      input: input,
      type: opts[:type] || infer_type(input),
      context: opts[:context],
      language: opts[:language],
      files: opts[:files],
      metadata: opts[:metadata] || %{},
      inserted_at: DateTime.utc_now()
    }
  end

  @doc """
  Generate a unique task ID.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    "task_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  @doc """
  Infer task type from input text.
  """
  @spec infer_type(String.t()) :: task_type()
  def infer_type(input) when is_binary(input) do
    input_lower = String.downcase(input)

    cond do
      matches_generate?(input_lower) -> :generate
      matches_review?(input_lower) -> :review
      matches_analyze?(input_lower) -> :analyze
      matches_refactor?(input_lower) -> :refactor
      matches_explain?(input_lower) -> :explain
      matches_fix?(input_lower) -> :fix
      true -> :generate
    end
  end

  defp matches_generate?(input) do
    String.contains?(input, ["generate", "create", "write", "build", "implement", "make"])
  end

  defp matches_review?(input) do
    String.contains?(input, ["review", "check", "audit", "inspect"])
  end

  defp matches_analyze?(input) do
    String.contains?(input, ["analyze", "analyse", "understand", "how does"])
  end

  defp matches_explain?(input) do
    String.contains?(input, ["explain", "what is", "what does", "describe", "clarify"])
  end

  defp matches_refactor?(input) do
    String.contains?(input, ["refactor", "improve", "optimize", "clean up", "restructure"])
  end

  defp matches_fix?(input) do
    String.contains?(input, ["fix", "bug", "error", "issue", "problem", "broken", "failing"])
  end

  @doc """
  Convert task to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = task) do
    %{
      id: task.id,
      input: task.input,
      type: task.type,
      context: task.context,
      language: task.language,
      files: task.files,
      metadata: task.metadata,
      inserted_at: task.inserted_at && DateTime.to_iso8601(task.inserted_at)
    }
  end
end
