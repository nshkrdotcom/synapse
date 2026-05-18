defmodule Synapse do
  @moduledoc """
  Headless product core for NSHKR Agent.

  This app owns product input normalization and product-safe view models. It
  does not own agent runtimes, workflow truth, memory truth, provider clients,
  connector sessions, or policy kernels.
  """

  @feature_status %{
    installation: :fixture_backed,
    runs: :fixture_backed,
    reviews: :fixture_backed,
    memory: :disabled,
    teams: :roadmap,
    evidence: :fixture_backed
  }

  @spec feature_status() :: map()
  def feature_status, do: @feature_status
end
