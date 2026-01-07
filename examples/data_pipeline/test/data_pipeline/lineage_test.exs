defmodule DataPipeline.LineageTest do
  use ExUnit.Case, async: true

  alias DataPipeline.Lineage

  describe "new/2" do
    test "creates a lineage record" do
      lineage = Lineage.new(:api, %{endpoint: "/data"})

      assert lineage.source == :api
      assert lineage.source_metadata == %{endpoint: "/data"}
      assert lineage.transformations == []
      assert %DateTime{} = lineage.created_at
    end
  end

  describe "add_transformation/3" do
    test "adds a transformation step" do
      lineage =
        Lineage.new(:database)
        |> Lineage.add_transformation(:extract, %{batch_id: 1})

      assert length(lineage.transformations) == 1
      [transformation] = lineage.transformations

      assert transformation.step == :extract
      assert transformation.metadata == %{batch_id: 1}
      assert %DateTime{} = transformation.timestamp
    end

    test "maintains transformation order" do
      lineage =
        Lineage.new(:api)
        |> Lineage.add_transformation(:extract)
        |> Lineage.add_transformation(:classify)
        |> Lineage.add_transformation(:transform)

      steps = Enum.map(lineage.transformations, & &1.step)
      assert steps == [:extract, :classify, :transform]
    end
  end

  describe "pipeline_path/1" do
    test "returns the pipeline path" do
      lineage =
        Lineage.new(:api)
        |> Lineage.add_transformation(:extract)
        |> Lineage.add_transformation(:classify)
        |> Lineage.add_transformation(:load)

      assert Lineage.pipeline_path(lineage) == [:extract, :classify, :load]
    end
  end

  describe "find_transformation/2" do
    test "finds a transformation by step name" do
      lineage =
        Lineage.new(:api)
        |> Lineage.add_transformation(:extract, %{count: 100})
        |> Lineage.add_transformation(:classify)

      transformation = Lineage.find_transformation(lineage, :extract)

      assert transformation.step == :extract
      assert transformation.metadata == %{count: 100}
    end

    test "returns nil for missing transformation" do
      lineage = Lineage.new(:api)

      assert is_nil(Lineage.find_transformation(lineage, :missing))
    end
  end

  describe "to_map/1 and from_map/1" do
    test "serializes and deserializes lineage" do
      original =
        Lineage.new(:database, %{table: "events"})
        |> Lineage.add_transformation(:extract)
        |> Lineage.add_transformation(:classify, %{result: :high})

      map = Lineage.to_map(original)
      restored = Lineage.from_map(map)

      assert restored.source == original.source
      assert restored.source_metadata == original.source_metadata
      assert length(restored.transformations) == length(original.transformations)
    end
  end
end
