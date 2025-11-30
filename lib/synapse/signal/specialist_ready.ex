defmodule Synapse.Signal.SpecialistReady do
  @moduledoc """
  DEPRECATED: Specialist readiness is now defined dynamically by registering
  the Code Review domain via `Synapse.Domains.CodeReview.register/0`.

  This module remains for documentation purposes and will be removed in a
  future release.
  """

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def schema, do: raise("Synapse.Signal.SpecialistReady is deprecated")

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def validate!(_payload), do: raise("Synapse.Signal.SpecialistReady is deprecated")
end
