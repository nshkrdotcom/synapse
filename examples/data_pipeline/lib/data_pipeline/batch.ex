defmodule DataPipeline.Batch do
  @moduledoc """
  Batch processing utilities for large datasets.

  Provides efficient batch processing with configurable parallelism and
  automatic error handling. Useful for processing large datasets that don't
  fit in memory or for rate-limiting API calls.

  ## Examples

      # Process records in batches of 100
      Batch.process_in_batches(records, 100, fn batch ->
        Enum.map(batch, &transform/1)
      end)

      # With options
      Batch.process_in_batches(records, 50, fn batch ->
        classify_batch(batch)
      end, max_concurrency: 5, timeout: 30_000)
  """

  require Logger

  @default_batch_size 100
  @default_max_concurrency 10
  @default_timeout 60_000

  @type processor_fn :: ([term()] -> [term()] | {:ok, [term()]} | {:error, term()})

  @doc """
  Processes a list of items in batches with configurable parallelism.

  ## Options

    * `:max_concurrency` - Maximum number of concurrent batch processors (default: 10)
    * `:timeout` - Timeout per batch in milliseconds (default: 60_000)
    * `:ordered` - Preserve input order in results (default: true)

  ## Examples

      Batch.process_in_batches(1..1000, 100, fn batch ->
        Enum.map(batch, &(&1 * 2))
      end)
  """
  @spec process_in_batches(Enumerable.t(), pos_integer(), processor_fn(), keyword()) ::
          [term()] | {:error, term()}
  def process_in_batches(items, batch_size \\ @default_batch_size, processor, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)

    items
    |> Stream.chunk_every(batch_size)
    |> Stream.with_index()
    |> Task.async_stream(
      fn {batch, index} ->
        Logger.debug("Processing batch #{index + 1} with #{length(batch)} items")
        process_batch(batch, index, processor)
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered
    )
    |> Enum.reduce_while([], fn
      {:ok, {:ok, results}}, acc ->
        {:cont, acc ++ results}

      {:ok, results}, acc when is_list(results) ->
        {:cont, acc ++ results}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:batch_exit, reason}}}

      error, _acc ->
        {:halt, {:error, {:batch_error, error}}}
    end)
  end

  @doc """
  Processes items in batches sequentially (no parallelism).

  Useful when order matters or when rate-limiting requires sequential processing.
  """
  @spec process_sequentially(Enumerable.t(), pos_integer(), processor_fn()) ::
          [term()] | {:error, term()}
  def process_sequentially(items, batch_size \\ @default_batch_size, processor) do
    items
    |> Stream.chunk_every(batch_size)
    |> Stream.with_index()
    |> Enum.reduce_while([], fn {batch, index}, acc ->
      case process_batch(batch, index, processor) do
        {:ok, results} ->
          {:cont, acc ++ results}

        results when is_list(results) ->
          {:cont, acc ++ results}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns statistics about batch processing.

  ## Examples

      Batch.batch_stats(10_000, 100)
      # => %{total_items: 10_000, batch_size: 100, num_batches: 100}
  """
  @spec batch_stats(integer(), pos_integer()) :: map()
  def batch_stats(total_items, batch_size) do
    num_batches = div(total_items + batch_size - 1, batch_size)

    %{
      total_items: total_items,
      batch_size: batch_size,
      num_batches: num_batches,
      last_batch_size: rem(total_items, batch_size),
      full_batches: div(total_items, batch_size)
    }
  end

  # Private helpers

  defp process_batch(batch, index, processor) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        processor.(batch)
      rescue
        error ->
          Logger.error("Batch #{index} failed: #{inspect(error)}")
          {:error, {:batch_processing_error, error}}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    Logger.debug("Batch #{index} completed in #{duration}ms")

    normalize_result(result)
  end

  defp normalize_result({:ok, results}) when is_list(results), do: {:ok, results}
  defp normalize_result({:error, _} = error), do: error
  defp normalize_result(results) when is_list(results), do: {:ok, results}
  defp normalize_result(other), do: {:ok, [other]}
end
