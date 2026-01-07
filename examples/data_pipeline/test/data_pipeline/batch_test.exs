defmodule DataPipeline.BatchTest do
  use ExUnit.Case, async: true

  alias DataPipeline.Batch

  describe "process_in_batches/4" do
    test "processes items in batches" do
      items = 1..250

      result =
        Batch.process_in_batches(items, 100, fn batch ->
          Enum.map(batch, &(&1 * 2))
        end)

      assert length(result) == 250
      assert Enum.at(result, 0) == 2
      assert Enum.at(result, 249) == 500
    end

    test "handles small batches" do
      items = [1, 2, 3]

      result =
        Batch.process_in_batches(items, 10, fn batch ->
          Enum.map(batch, &(&1 * 2))
        end)

      assert result == [2, 4, 6]
    end

    test "handles empty list" do
      result =
        Batch.process_in_batches([], 100, fn batch ->
          Enum.map(batch, &(&1 * 2))
        end)

      assert result == []
    end

    test "handles errors in processor" do
      items = 1..10

      result =
        Batch.process_in_batches(items, 5, fn _batch ->
          {:error, :processing_failed}
        end)

      assert {:error, :processing_failed} = result
    end
  end

  describe "process_sequentially/3" do
    test "processes batches in order" do
      items = 1..100

      result =
        Batch.process_sequentially(items, 25, fn batch ->
          Enum.map(batch, &(&1 * 2))
        end)

      assert length(result) == 100
      assert Enum.at(result, 0) == 2
      assert Enum.at(result, 99) == 200
    end
  end

  describe "batch_stats/2" do
    test "calculates batch statistics" do
      stats = Batch.batch_stats(1000, 100)

      assert stats.total_items == 1000
      assert stats.batch_size == 100
      assert stats.num_batches == 10
      assert stats.last_batch_size == 0
      assert stats.full_batches == 10
    end

    test "handles partial last batch" do
      stats = Batch.batch_stats(1050, 100)

      assert stats.num_batches == 11
      assert stats.last_batch_size == 50
      assert stats.full_batches == 10
    end
  end
end
