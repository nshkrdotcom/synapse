defmodule Synapse.WorkEmitter.Adapter do
  @moduledoc """
  Adapter behaviour for emitting NSAI.Work job events.
  """

  @callback emit(atom(), Work.Job.t(), keyword()) :: :ok | {:error, term()}
end
