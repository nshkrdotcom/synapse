defmodule Synapse.WorkEmitter.Adapters.Noop do
  @moduledoc false

  @behaviour Synapse.WorkEmitter.Adapter

  @impl true
  def emit(_event, _job, _opts), do: :ok
end
