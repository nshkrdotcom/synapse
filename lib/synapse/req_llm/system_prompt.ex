defmodule Synapse.ReqLLM.SystemPrompt do
  @moduledoc """
  Centralized system prompt resolution with documented precedence rules.

  ## Precedence Hierarchy

  System prompts are resolved in this order (highest to lowest priority):

  1. **Request-level system messages** - Messages with `role: "system"` in params
  2. **Profile-level** - `:system_prompt` in profile configuration
  3. **Global-level** - `:system_prompt` in global configuration
  4. **Default** - `"You are a helpful assistant."`

  ## Examples

      # Profile-level system prompt
      config :synapse, Synapse.ReqLLM,
        profiles: %{
          openai: [
            system_prompt: "You are a code reviewer"  # ← Used if no request-level
          ]
        }

      # Request-level override (highest priority)
      ReqLLM.chat_completion(
        %{
          prompt: "Review this code",
          messages: [
            %{role: "system", content: "You are a Rust expert"}  # ← Wins!
          ]
        }
      )

  ## Provider-Specific Handling

  - **OpenAI**: System prompt becomes first message in messages array
  - **Gemini**: System prompts merged into `system_instruction` field with `\\n\\n` separator
  """

  @default_system_prompt "You are a helpful assistant."

  @doc """
  Resolves the base system prompt from configuration hierarchy.

  This handles the profile > global > default precedence.
  Request-level system messages are handled separately by providers.

  ## Parameters

    * `profile_config` - Profile configuration keyword list
    * `global_config` - Global configuration map

  ## Returns

  The resolved system prompt string.

  ## Examples

      iex> resolve(
      ...>   [system_prompt: "Profile prompt"],
      ...>   %{system_prompt: "Global prompt"}
      ...> )
      "Profile prompt"

      iex> resolve(
      ...>   [],
      ...>   %{system_prompt: "Global prompt"}
      ...> )
      "Global prompt"

      iex> resolve([], %{})
      "You are a helpful assistant."
  """
  def resolve(profile_config, global_config) do
    Keyword.get(profile_config, :system_prompt) ||
      Map.get(global_config, :system_prompt) ||
      @default_system_prompt
  end

  @doc """
  Extracts system messages from a message list.

  Returns `{system_messages, other_messages}`.

  ## Examples

      iex> extract_system_messages([
      ...>   %{"role" => "system", "content" => "You are an expert"},
      ...>   %{"role" => "user", "content" => "Hello"}
      ...> ])
      {
        [%{"role" => "system", "content" => "You are an expert"}],
        [%{"role" => "user", "content" => "Hello"}]
      }
  """
  def extract_system_messages(messages) when is_list(messages) do
    Enum.split_with(messages, fn
      %{"role" => "system"} -> true
      %{role: "system"} -> true
      _ -> false
    end)
  end

  def extract_system_messages(_), do: {[], []}

  @doc """
  Merges multiple system prompt sources into a single text.

  Used by Gemini provider to combine base prompt + request system messages.

  ## Parameters

    * `base_prompt` - The resolved base system prompt (from resolve/2)
    * `system_messages` - List of system messages from request (from extract_system_messages/1)

  ## Returns

  Single merged system prompt text with duplicates removed.

  ## Examples

      iex> merge("You are helpful", [
      ...>   %{"content" => "You are an expert"},
      ...>   %{"content" => "You are helpful"}  # Duplicate
      ...> ])
      "You are helpful\\n\\nYou are an expert"
  """
  def merge(base_prompt, system_messages) when is_list(system_messages) do
    all_prompts =
      [base_prompt | Enum.map(system_messages, &extract_content/1)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    case all_prompts do
      [] -> @default_system_prompt
      [single] -> single
      multiple -> Enum.join(multiple, "\n\n")
    end
  end

  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(_), do: nil

  @doc """
  Returns the default system prompt.
  """
  def default, do: @default_system_prompt
end
