defmodule CodingAgent.TaskTest do
  use ExUnit.Case, async: true

  alias CodingAgent.Task

  describe "new/2" do
    test "creates task with required fields" do
      task = Task.new("Write a hello world function")

      assert task.id =~ ~r/^task_[a-f0-9]{16}$/
      assert task.input == "Write a hello world function"
      assert task.type == :generate
      assert %DateTime{} = task.inserted_at
    end

    test "accepts explicit type override" do
      task = Task.new("Some input", type: :review)

      assert task.type == :review
    end

    test "accepts context and language" do
      task = Task.new("Review this", context: "def foo, do: :bar", language: "elixir")

      assert task.context == "def foo, do: :bar"
      assert task.language == "elixir"
    end

    test "accepts files list" do
      task = Task.new("Analyze", files: ["lib/foo.ex", "lib/bar.ex"])

      assert task.files == ["lib/foo.ex", "lib/bar.ex"]
    end

    test "accepts metadata map" do
      task = Task.new("Generate", metadata: %{author: "test", priority: :high})

      assert task.metadata == %{author: "test", priority: :high}
    end
  end

  describe "infer_type/1" do
    test "infers :generate for generation keywords" do
      assert Task.infer_type("Generate a function") == :generate
      assert Task.infer_type("Create a module") == :generate
      assert Task.infer_type("Write a test") == :generate
      assert Task.infer_type("Build a parser") == :generate
      assert Task.infer_type("Implement the feature") == :generate
    end

    test "infers :review for review keywords" do
      assert Task.infer_type("Review this code") == :review
      assert Task.infer_type("Check for issues") == :review
      assert Task.infer_type("Audit the security") == :review
    end

    test "infers :analyze for analysis keywords" do
      assert Task.infer_type("Analyze this algorithm") == :analyze
      assert Task.infer_type("How does this work?") == :analyze
      assert Task.infer_type("Understand the flow") == :analyze
    end

    test "infers :explain for explanation keywords" do
      assert Task.infer_type("Explain this function") == :explain
      assert Task.infer_type("What is this pattern?") == :explain
      assert Task.infer_type("Describe the architecture") == :explain
    end

    test "infers :refactor for refactoring keywords" do
      assert Task.infer_type("Refactor this module") == :refactor
      assert Task.infer_type("Improve the code") == :refactor
      assert Task.infer_type("Optimize performance") == :refactor
      assert Task.infer_type("Clean up this mess") == :refactor
    end

    test "infers :fix for bug-fixing keywords" do
      assert Task.infer_type("Fix this bug") == :fix
      assert Task.infer_type("There's an error here") == :fix
      assert Task.infer_type("This is broken") == :fix
      assert Task.infer_type("Tests are failing") == :fix
    end

    test "defaults to :generate for unknown input" do
      assert Task.infer_type("Hello world") == :generate
      assert Task.infer_type("Do something") == :generate
    end
  end

  describe "to_map/1" do
    test "converts task to serializable map" do
      task = Task.new("Test input", type: :review, language: "elixir")
      map = Task.to_map(task)

      assert map.id == task.id
      assert map.input == "Test input"
      assert map.type == :review
      assert map.language == "elixir"
      assert is_binary(map.inserted_at)
    end
  end
end
