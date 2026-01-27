defmodule Synapse.RunIndex.Adapter do
  @moduledoc """
  Adapter behaviour for emitting RunIndex records.
  """

  @callback write_run(map(), keyword()) :: :ok | {:error, term()}
  @callback write_step(map(), keyword()) :: :ok | {:error, term()}
end
