defmodule Synapse.Arbitration do
  @moduledoc """
  Availability for the post-MVP multi-agent arbitration surface.

  P06 composes the single-agent lifecycle only. Until AppKit projects an
  executable coordination session, arbitration stays absent instead of
  advertising a fixture consensus or routing a decision to an unrelated
  review.
  """

  alias AppKit.Core.ProductSurface.Availability

  @spec availability(keyword()) :: Availability.t()
  def availability(_opts \\ []) do
    {:ok, availability} = Availability.new({:unavailable, :not_supported})
    availability
  end

  @spec list_sessions(keyword()) :: []
  def list_sessions(_opts \\ []), do: []

  @spec get_session(String.t(), keyword()) :: {:error, :arbitration_not_supported}
  def get_session(_id_or_ref, _opts \\ []), do: {:error, :arbitration_not_supported}

  @spec record_final_decision(String.t(), map(), keyword()) ::
          {:error, :arbitration_not_supported}
  def record_final_decision(_id_or_ref, _attrs, _opts \\ []),
    do: {:error, :arbitration_not_supported}
end
