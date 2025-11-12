defmodule Synapse.Actions.Review.ClassifyChangeTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Review.ClassifyChange

  describe "ClassifyChange action" do
    test "classifies small, unlabelled diffs as fast_path" do
      params = %{
        files_changed: 3,
        labels: [],
        intent: "feature",
        risk_factor: 0.0
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :fast_path
      assert is_binary(result.rationale)
    end

    test "classifies large diffs (>50 files) as deep_review" do
      params = %{
        files_changed: 75,
        labels: [],
        intent: "feature",
        risk_factor: 0.0
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :deep_review
      assert result.rationale =~ "50"
    end

    test "classifies changes with security label as deep_review" do
      params = %{
        files_changed: 5,
        labels: ["security"],
        intent: "feature",
        risk_factor: 0.0
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :deep_review
      assert result.rationale =~ "security"
    end

    test "classifies changes with performance label as deep_review" do
      params = %{
        files_changed: 5,
        labels: ["performance"],
        intent: "feature",
        risk_factor: 0.0
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :deep_review
      assert result.rationale =~ "performance"
    end

    test "classifies hotfix intent as fast_path" do
      params = %{
        files_changed: 10,
        labels: [],
        intent: "hotfix",
        risk_factor: 0.0
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :fast_path
      assert result.rationale =~ "hotfix"
    end

    test "uses risk_factor in classification when provided" do
      params = %{
        files_changed: 10,
        labels: [],
        intent: "feature",
        risk_factor: 0.8
      }

      assert {:ok, result} = ClassifyChange.run(params, %{})
      assert result.path == :deep_review
      assert result.rationale =~ "risk"
    end

    test "returns validation error for missing required fields" do
      params = %{
        files_changed: 5
        # Missing labels, intent
      }

      # Use Jido.Exec.run to trigger schema validation
      assert {:error, error} = Jido.Exec.run(ClassifyChange, params, %{})
      assert error.type == :validation_error
    end

    test "returns validation error for invalid files_changed type" do
      params = %{
        files_changed: "not a number",
        labels: [],
        intent: "feature"
      }

      # Use Jido.Exec.run to trigger schema validation
      assert {:error, error} = Jido.Exec.run(ClassifyChange, params, %{})
      assert error.type == :validation_error
    end

    test "includes review_id in result when provided in context" do
      params = %{
        files_changed: 5,
        labels: [],
        intent: "feature",
        risk_factor: 0.0
      }

      context = %{review_id: "test_review_123"}

      assert {:ok, result} = ClassifyChange.run(params, context)
      assert result.review_id == "test_review_123"
    end

    test "defaults risk_factor to 0.0 when not provided" do
      params = %{
        files_changed: 5,
        labels: [],
        intent: "feature"
      }

      # Use Exec.run to get default value from schema
      assert {:ok, result} = Jido.Exec.run(ClassifyChange, params, %{})
      assert result.path == :fast_path
    end
  end
end
