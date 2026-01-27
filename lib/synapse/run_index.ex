defmodule Synapse.RunIndex do
  @moduledoc false

  alias Synapse.RunIndex.Adapters.Noop

  @default_adapter Noop

  @spec write_run(map(), keyword()) :: :ok | {:error, term()}
  def write_run(attrs, opts \\ []) when is_map(attrs) do
    adapter = adapter(opts)
    adapter.write_run(normalize_run(attrs), merge_opts(opts, :run_index_opts))
  end

  @spec write_step(map(), keyword()) :: :ok | {:error, term()}
  def write_step(attrs, opts \\ []) when is_map(attrs) do
    adapter = adapter(opts)
    adapter.write_step(normalize_step(attrs), merge_opts(opts, :run_index_opts))
  end

  defp adapter(opts) do
    Keyword.get(opts, :run_index_adapter) ||
      Application.get_env(:synapse, :run_index_adapter, @default_adapter)
  end

  defp normalize_run(attrs) do
    run_id = Map.get(attrs, :id) || Map.get(attrs, :run_id) || Ecto.UUID.generate()

    attrs
    |> Map.put_new(:id, run_id)
    |> Map.put_new(:runtime, "synapse")
    |> Map.put_new(:runtime_ref, runtime_ref(attrs, run_id))
    |> Map.update(:status, nil, &normalize_status/1)
    |> Map.update(:scheduled_at, nil, &normalize_datetime/1)
    |> Map.update(:started_at, nil, &normalize_datetime/1)
    |> Map.update(:finished_at, nil, &normalize_datetime/1)
  end

  defp runtime_ref(attrs, run_id) do
    Map.get(attrs, :runtime_ref) || Map.get(attrs, :request_id) || to_string(run_id)
  end

  defp normalize_step(attrs) do
    attrs
    |> Map.update(:status, nil, &normalize_status/1)
    |> Map.update(:started_at, nil, &normalize_datetime/1)
    |> Map.update(:finished_at, nil, &normalize_datetime/1)
    |> Map.update(:step_key, nil, &normalize_step_key/1)
  end

  defp normalize_status(nil), do: nil
  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(status), do: status

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_datetime(value), do: value

  defp normalize_step_key(nil), do: nil
  defp normalize_step_key(step_key) when is_atom(step_key), do: Atom.to_string(step_key)
  defp normalize_step_key(step_key), do: step_key

  defp merge_opts(opts, key) do
    extra = Keyword.get(opts, key, []) || []

    opts
    |> Keyword.merge(extra)
    |> Keyword.delete(key)
  end
end
