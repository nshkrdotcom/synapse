defmodule Synapse.Signal.ReviewRequest do
  @moduledoc """
  DEPRECATED: Review request signals are now registered dynamically via
  `Synapse.Domains.CodeReview.register/0`.

  This module remains for documentation purposes and will be removed in a
  future release.
  """

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def schema, do: raise("Synapse.Signal.ReviewRequest is deprecated")

  @deprecated "Use Synapse.Domains.CodeReview.register/0 instead"
  def validate!(_payload), do: raise("Synapse.Signal.ReviewRequest is deprecated")
end
