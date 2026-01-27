defmodule Synapse.RunIndex.Adapters.Noop do
  @moduledoc false

  @behaviour Synapse.RunIndex.Adapter

  @impl true
  def write_run(_attrs, _opts), do: :ok

  @impl true
  def write_step(_attrs, _opts), do: :ok
end
