defmodule Synapse.Signal.ReviewResult do
  @moduledoc """
  DEPRECATED: Review result signals are registered dynamically through
  `Synapse.Domains.CodeReview.register/0`.

  This module remains for backward compatibility and will be removed in a
  future release.
  """

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def schema, do: raise("Synapse.Signal.ReviewResult is deprecated")

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def validate!(_payload), do: raise("Synapse.Signal.ReviewResult is deprecated")
end
