defmodule Synapse do
  @moduledoc """
  Headless product core for NSHKR Agent.

  This app owns product input normalization and product-safe view models. It
  does not own agent runtimes, workflow truth, memory truth, provider clients,
  connector sessions, or policy kernels.
  """

  @spec feature_status() :: map()
  def feature_status, do: Synapse.ProductProfile.feature_status()
end
