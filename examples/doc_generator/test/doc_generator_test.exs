defmodule DocGeneratorTest do
  use ExUnit.Case, async: false

  doctest DocGenerator

  describe "available_providers/0" do
    test "returns list of available providers" do
      providers = DocGenerator.available_providers()
      assert is_list(providers)
      assert Enum.all?(providers, &(&1 in [:claude, :codex, :gemini]))
    end
  end

  describe "provider_available?/1" do
    test "checks individual provider availability" do
      # In test env, all providers should be unavailable
      assert DocGenerator.provider_available?(:claude) == false
      assert DocGenerator.provider_available?(:codex) == false
      assert DocGenerator.provider_available?(:gemini) == false
    end

    test "returns false for unknown providers" do
      assert DocGenerator.provider_available?(:unknown) == false
    end
  end

  describe "default_style/0" do
    test "returns default documentation style" do
      assert DocGenerator.default_style() in [:formal, :casual, :tutorial, :reference]
    end
  end
end
