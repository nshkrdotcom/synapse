defmodule Synapse.ReqLLM.SystemPromptTest do
  use ExUnit.Case, async: true

  alias Synapse.ReqLLM.SystemPrompt

  describe "resolve/2" do
    test "uses profile-level system prompt when available" do
      profile_config = [system_prompt: "Profile prompt"]
      global_config = %{system_prompt: "Global prompt"}

      assert SystemPrompt.resolve(profile_config, global_config) == "Profile prompt"
    end

    test "falls back to global system prompt when profile has none" do
      profile_config = []
      global_config = %{system_prompt: "Global prompt"}

      assert SystemPrompt.resolve(profile_config, global_config) == "Global prompt"
    end

    test "uses default when neither profile nor global specify prompt" do
      profile_config = []
      global_config = %{}

      assert SystemPrompt.resolve(profile_config, global_config) == "You are a helpful assistant."
    end

    test "profile-level overrides global-level" do
      profile_config = [system_prompt: "Profile wins"]
      global_config = %{system_prompt: "Global loses"}

      assert SystemPrompt.resolve(profile_config, global_config) == "Profile wins"
    end

    test "handles nil values correctly" do
      profile_config = [system_prompt: nil]
      global_config = %{system_prompt: "Global prompt"}

      # nil is treated as absent, so falls back to global
      assert SystemPrompt.resolve(profile_config, global_config) == "Global prompt"
    end
  end

  describe "extract_system_messages/1" do
    test "separates system messages from other messages" do
      messages = [
        %{"role" => "system", "content" => "System 1"},
        %{"role" => "user", "content" => "User message"},
        %{"role" => "system", "content" => "System 2"},
        %{"role" => "assistant", "content" => "Assistant message"}
      ]

      {system, others} = SystemPrompt.extract_system_messages(messages)

      assert length(system) == 2
      assert length(others) == 2
      assert Enum.all?(system, &(&1["role"] == "system"))
      assert Enum.all?(others, &(&1["role"] in ["user", "assistant"]))
    end

    test "handles atom key messages" do
      messages = [
        %{role: "system", content: "System prompt"},
        %{role: "user", content: "User message"}
      ]

      {system, others} = SystemPrompt.extract_system_messages(messages)

      assert length(system) == 1
      assert length(others) == 1
    end

    test "returns empty lists when no messages" do
      assert SystemPrompt.extract_system_messages([]) == {[], []}
    end

    test "returns empty system list when no system messages" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi"}
      ]

      {system, others} = SystemPrompt.extract_system_messages(messages)

      assert system == []
      assert length(others) == 2
    end
  end

  describe "merge/2" do
    test "combines base prompt with system messages" do
      base = "You are helpful"

      system_messages = [
        %{"content" => "You are an expert"},
        %{"content" => "You are concise"}
      ]

      result = SystemPrompt.merge(base, system_messages)

      assert result == "You are helpful\n\nYou are an expert\n\nYou are concise"
    end

    test "removes duplicate prompts" do
      base = "You are helpful"

      system_messages = [
        %{"content" => "You are an expert"},
        %{"content" => "You are helpful"}
        # Duplicate!
      ]

      result = SystemPrompt.merge(base, system_messages)

      # Should only appear once
      assert result == "You are helpful\n\nYou are an expert"
    end

    test "handles empty system messages" do
      base = "You are helpful"

      result = SystemPrompt.merge(base, [])

      assert result == "You are helpful"
    end

    test "filters out nil and empty content" do
      base = "You are helpful"

      system_messages = [
        %{"content" => ""},
        %{"content" => "Valid content"},
        %{"content" => nil}
      ]

      result = SystemPrompt.merge(base, system_messages)

      assert result == "You are helpful\n\nValid content"
    end

    test "handles atom key messages" do
      base = "Base prompt"

      system_messages = [
        %{content: "Message 1"},
        %{content: "Message 2"}
      ]

      result = SystemPrompt.merge(base, system_messages)

      assert result == "Base prompt\n\nMessage 1\n\nMessage 2"
    end

    test "returns default when all prompts are empty" do
      result = SystemPrompt.merge("", [%{"content" => ""}, %{"content" => nil}])

      assert result == "You are a helpful assistant."
    end
  end

  describe "default/0" do
    test "returns the default system prompt" do
      assert SystemPrompt.default() == "You are a helpful assistant."
    end
  end

  describe "integration: precedence documentation" do
    test "documents expected precedence behavior across providers" do
      # This test documents the precedence rules without running providers
      # Actual provider behavior is tested in req_llm_action_test.exs

      # Precedence order (highest to lowest):
      # 1. Request-level system messages (in params.messages)
      # 2. Profile-level :system_prompt
      # 3. Global-level :system_prompt
      # 4. Provider default

      # OpenAI behavior:
      # - Base system prompt (resolved via precedence) goes first
      # - Request system messages preserved after base
      # - All system messages sent in messages array

      # Gemini behavior:
      # - Base system prompt + request system messages merged
      # - Joined with \n\n separator
      # - Duplicates removed
      # - Sent in system_instruction field

      # This test serves as documentation
      assert true
    end
  end
end
