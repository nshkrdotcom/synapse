defmodule DataPipeline.Workflows.SimpleETLTest do
  use ExUnit.Case, async: true

  alias DataPipeline.Workflows.SimpleETL
  alias DataPipeline.Fixtures

  describe "run/2" do
    test "runs a simple ETL pipeline" do
      data = Fixtures.sample_data() |> Enum.take(5)

      assert {:ok, result} = SimpleETL.run(data)

      assert result.count == 5
      assert result.destination == :memory
      assert is_list(result.lineage)
      assert length(result.lineage) == 5
    end

    test "runs with custom destination" do
      data = Fixtures.sample_data() |> Enum.take(3)

      assert {:ok, result} = SimpleETL.run(data, destination: :s3)

      assert result.destination == :s3
    end

    test "runs with different transformer" do
      data = Fixtures.sample_data() |> Enum.take(3)

      assert {:ok, result} = SimpleETL.run(data, transformer: :enrich)

      assert result.count == 3
    end

    test "skips validation when disabled" do
      data = [%{text: "Test"}]

      assert {:ok, result} = SimpleETL.run(data, validate: false)

      assert result.count == 1
    end

    test "handles empty data" do
      assert {:ok, result} = SimpleETL.run([])

      assert result.count == 0
    end
  end
end
