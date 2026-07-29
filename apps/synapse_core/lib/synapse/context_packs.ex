defmodule Synapse.ContextPacks do
  @moduledoc """
  Product projections of immutable AppKit memory retrieval snapshots.
  """

  alias Synapse.Memory

  @spec list_context_packs(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_context_packs(opts \\ []) when is_list(opts) do
    with {:ok, memories} <- Memory.list_memories(opts) do
      case memories do
        [] -> {:ok, []}
        [_first | _rest] -> {:ok, [context_pack(memories)]}
      end
    end
  end

  @spec get_context_pack(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_context_pack(id_or_ref, opts \\ []) when is_binary(id_or_ref) and is_list(opts) do
    decoded_id = decode_route_id(id_or_ref)

    with {:ok, packs} <- list_context_packs(opts),
         %{} = pack <-
           Enum.find(packs, fn pack ->
             pack.id in [id_or_ref, decoded_id] or pack.ref in [id_or_ref, decoded_id]
           end) do
      {:ok, pack}
    else
      nil -> {:error, :context_pack_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec surface_status(keyword()) :: map()
  def surface_status(opts \\ []), do: Memory.surface_status(opts)

  defp context_pack(memories) do
    first = hd(memories)
    projection = first.projection

    entries =
      Enum.map(memories, fn memory ->
        %{
          ref: memory.memory_ref,
          state: memory.state,
          evidence_ref: memory.evidence_ref,
          proof_token_ref: memory.proof_token_ref,
          reason_codes: memory.reason_codes
        }
      end)

    %{
      id: URI.encode_www_form(projection.proof_token_ref),
      ref: projection.proof_token_ref,
      mode: :retrieval_snapshot,
      run_ref: metadata_value(projection.metadata || %{}, :run_ref),
      trace_id: metadata_value(projection.metadata || %{}, :trace_id),
      context_hash: projection.proof_hash,
      snapshot_epoch: projection.snapshot_epoch,
      commit_lsn: projection.commit_lsn,
      redaction_policy_ref: projection.redaction_posture,
      included: bucket(entries, :included),
      denied: bucket(entries, :denied),
      stale: bucket(entries, :stale),
      revoked: bucket(entries, :revoked),
      candidates: bucket(entries, :candidate),
      degraded: bucket(entries, :degraded),
      feature_status: :durable_retrieval_snapshot
    }
  end

  defp bucket(entries, state), do: Enum.filter(entries, &(&1.state == state))

  defp decode_route_id(value) do
    URI.decode_www_form(value)
  rescue
    ArgumentError -> value
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
end
