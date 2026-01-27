defmodule Synapse.RunIndex.Adapters.Ecto do
  @moduledoc """
  Ecto adapter for writing RunIndex records to the run_index schema.
  """

  @behaviour Synapse.RunIndex.Adapter

  @default_prefix "run_index"

  @impl true
  def write_run(attrs, opts) when is_map(attrs) do
    with {:ok, repo} <- fetch_repo(opts) do
      now = utc_now()

      row =
        attrs
        |> normalize_fields()
        |> Map.put_new(:inserted_at, now)
        |> Map.put(:updated_at, now)

      insert_all(repo, "runs", [row], opts)
    end
  end

  @impl true
  def write_step(attrs, opts) when is_map(attrs) do
    with {:ok, repo} <- fetch_repo(opts) do
      now = utc_now()

      row =
        attrs
        |> normalize_fields()
        |> Map.put_new(:inserted_at, now)
        |> Map.put(:updated_at, now)

      insert_all(repo, "steps", [row], opts)
    end
  end

  defp fetch_repo(opts) do
    case Keyword.get(opts, :repo) || Application.get_env(:synapse, :run_index_repo) do
      nil -> {:error, :missing_repo}
      repo -> {:ok, repo}
    end
  end

  defp insert_all(repo, table, entries, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    repo.insert_all(table, entries,
      prefix: prefix,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:id]
    )

    :ok
  rescue
    error -> {:error, error}
  end

  defp normalize_fields(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {key, normalize_value(value)} end)
  end

  defp normalize_value(%DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_value(value), do: value

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
