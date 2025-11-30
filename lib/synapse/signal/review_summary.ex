defmodule Synapse.Signal.ReviewSummary do
  @moduledoc """
  DEPRECATED: Review summary signals are now registered dynamically via
  `Synapse.Domains.CodeReview.register/0`.

  This module remains for backward compatibility and will be removed in a
  future release.
  """

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def schema, do: raise("Synapse.Signal.ReviewSummary is deprecated")

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def validate!(_payload), do: raise("Synapse.Signal.ReviewSummary is deprecated")
end
