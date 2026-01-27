defmodule Synapse.WorkEmitter do
  @moduledoc false

  alias Synapse.WorkEmitter.Adapters.Noop

  @default_adapter Noop

  @type event :: :started | :succeeded | :failed | :canceled

  @spec emit(event(), Work.Job.t(), keyword()) :: :ok | {:error, term()}
  def emit(event, %Work.Job{} = job, opts \\ []) do
    opts = merge_opts(opts, :work_opts)
    adapter = adapter(opts)
    adapter.emit(event, job, opts)
  end

  defp adapter(opts) do
    Keyword.get(opts, :work_adapter) ||
      Application.get_env(:synapse, :work_adapter, @default_adapter)
  end

  defp merge_opts(opts, key) do
    extra = Keyword.get(opts, key, []) || []

    opts
    |> Keyword.merge(extra)
    |> Keyword.delete(key)
  end
end
