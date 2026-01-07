defmodule CodingAgent.RouterTest do
  use ExUnit.Case, async: true

  alias CodingAgent.{Router, Task}

  describe "route/1" do
    test "routes :generate tasks to Claude" do
      task = Task.new("Generate code", type: :generate)
      assert Router.route(task) == :claude
    end

    test "routes :review tasks to Codex" do
      task = Task.new("Review code", type: :review)
      assert Router.route(task) == :codex
    end

    test "routes :analyze tasks to Gemini" do
      task = Task.new("Analyze code", type: :analyze)
      assert Router.route(task) == :gemini
    end

    test "routes :explain tasks to Gemini" do
      task = Task.new("Explain code", type: :explain)
      assert Router.route(task) == :gemini
    end

    test "routes :refactor tasks to Claude" do
      task = Task.new("Refactor code", type: :refactor)
      assert Router.route(task) == :claude
    end

    test "routes :fix tasks to Codex" do
      task = Task.new("Fix bug", type: :fix)
      assert Router.route(task) == :codex
    end
  end

  describe "providers_for/1" do
    test "returns ranked list with primary provider first" do
      assert Router.providers_for(:generate) == [:claude, :codex, :gemini]
      assert Router.providers_for(:review) == [:codex, :claude, :gemini]
      assert Router.providers_for(:analyze) == [:gemini, :claude, :codex]
    end
  end

  describe "available_providers/0" do
    test "returns all provider atoms" do
      assert Router.available_providers() == [:claude, :codex, :gemini]
    end
  end

  describe "routing_table/0" do
    test "returns the routing configuration" do
      table = Router.routing_table()

      assert is_map(table)
      assert table[:generate] == :claude
      assert table[:review] == :codex
    end
  end
end
