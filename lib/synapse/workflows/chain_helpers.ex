defmodule Synapse.Workflows.ChainHelpers do
  @moduledoc false
  # Internal helpers for chain-based workflows

  @doc """
  Validates that required input fields are present.

  Returns `:ok` if validation passes, or `{:error, Jido.Error.t()}` with details about missing fields.
  """
  @spec validate_input(map()) :: :ok | {:error, Jido.Error.t()}
  def validate_input(input) do
    required = [:message, :intent]
    missing = Enum.filter(required, &(!Map.has_key?(input, &1)))

    if Enum.empty?(missing) do
      :ok
    else
      {:error,
       Jido.Error.validation_error(
         "Missing required fields: #{inspect(missing)}",
         %{required: required, missing: missing}
       )}
    end
  end

  @doc """
  Builds an LLM prompt from review context.

  Includes the code being reviewed, critic feedback, and any constraints.
  """
  @spec build_llm_prompt(String.t(), list(String.t()), map()) :: String.t()
  def build_llm_prompt(message, constraints, review_result) do
    constraints_text = format_constraints(constraints)
    review_json = Jason.encode!(review_result)

    """
    Provide concrete next steps to strengthen the submission.

    Code:
    #{message}

    Critic feedback:
    #{review_json}
    #{constraints_text}

    Focus on actionable improvements and specific suggestions.
    """
  end

  @doc """
  Generates a unique request ID for tracking.
  """
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
    |> String.downcase()
  end

  # Private helpers

  defp format_constraints([]), do: ""

  defp format_constraints(constraints) do
    "\n\nConstraints to consider:\n" <>
      Enum.map_join(constraints, "\n", fn c -> "- #{c}" end)
  end
end
