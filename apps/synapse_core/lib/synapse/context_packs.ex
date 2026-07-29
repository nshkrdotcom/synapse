defmodule Synapse.ContextPacks.Entry do
  @moduledoc "Refs-only memory disposition inside one immutable retrieval proof."

  @enforce_keys [
    :ref,
    :state,
    :memory_class,
    :proof_token_ref,
    :reason_codes,
    :retention_state,
    :deletion_state,
    :reindex_state
  ]
  defstruct @enforce_keys ++
              [
                :evidence_ref,
                :content_artifact_ref,
                :retention_policy_ref,
                :deleted_at,
                :deletion_reason,
                :index_revision,
                :reindex_reason
              ]

  @type t :: %__MODULE__{}
end

defmodule Synapse.ContextPacks.Pack do
  @moduledoc "Immutable AppKit retrieval proof projected for context inspection."

  @enforce_keys [
    :id,
    :ref,
    :mode,
    :context_hash,
    :snapshot_epoch,
    :commit_lsn,
    :redaction_policy_ref,
    :included,
    :denied,
    :stale,
    :revoked,
    :candidates,
    :degraded,
    :working_memory_refs,
    :episodic_memory_refs,
    :retention_states,
    :deletion_states,
    :reindex_states,
    :feature_status
  ]
  defstruct @enforce_keys ++
              [
                :run_ref,
                :trace_id,
                :retrieval_snapshot_ref,
                :context_manifest_artifact_ref,
                :index_revision,
                exclusion_refs: []
              ]

  @type t :: %__MODULE__{}
end

defmodule Synapse.ContextPacks do
  @moduledoc """
  Product projections of immutable AppKit memory retrieval snapshots.
  """

  alias Synapse.Memory
  alias Synapse.ContextPacks.{Entry, Pack}

  @spec list_context_packs(keyword()) :: {:ok, [Pack.t()]} | {:error, term()}
  def list_context_packs(opts \\ []) when is_list(opts) do
    with {:ok, memories} <- Memory.list_memories(opts) do
      case memories do
        [] -> {:ok, []}
        [_first | _rest] -> build_context_pack(memories)
      end
    end
  end

  @spec get_context_pack(String.t(), keyword()) :: {:ok, Pack.t()} | {:error, term()}
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

  defp build_context_pack(memories) do
    if one_snapshot?(memories) do
      {:ok, [context_pack(memories)]}
    else
      {:error, :mixed_memory_snapshot_projection}
    end
  end

  defp context_pack(memories) do
    first = hd(memories)
    projection = first.projection

    entries =
      Enum.map(memories, fn memory ->
        %Entry{
          ref: memory.memory_ref,
          state: memory.state,
          memory_class: memory.memory_class,
          evidence_ref: memory.evidence_ref,
          proof_token_ref: memory.proof_token_ref,
          reason_codes: memory.reason_codes,
          content_artifact_ref: memory.content_artifact_ref,
          retention_state: memory.lifecycle.retention_state,
          retention_policy_ref: memory.lifecycle.retention_policy_ref,
          deletion_state: memory.lifecycle.deletion_state,
          deleted_at: memory.lifecycle.deleted_at,
          deletion_reason: memory.lifecycle.deletion_reason,
          reindex_state: memory.lifecycle.reindex_state,
          index_revision: memory.lifecycle.index_revision,
          reindex_reason: memory.lifecycle.reindex_reason
        }
      end)

    %Pack{
      id: URI.encode_www_form(projection.proof_token_ref),
      ref: projection.proof_token_ref,
      mode: :retrieval_snapshot,
      run_ref: metadata_value(projection.metadata || %{}, :run_ref),
      trace_id: metadata_value(projection.metadata || %{}, :trace_id),
      retrieval_snapshot_ref: first.snapshot.retrieval_snapshot_ref,
      context_manifest_artifact_ref:
        optional_string(
          metadata_value(projection.metadata || %{}, :context_manifest_artifact_ref)
        ),
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
      working_memory_refs: class_refs(memories, :working),
      episodic_memory_refs: class_refs(memories, :episodic),
      exclusion_refs: string_list(metadata_value(projection.metadata || %{}, :exclusion_refs)),
      retention_states: distinct_lifecycle(entries, :retention_state),
      deletion_states: distinct_lifecycle(entries, :deletion_state),
      reindex_states: distinct_lifecycle(entries, :reindex_state),
      index_revision: one_index_revision(entries),
      feature_status: :durable_retrieval_snapshot
    }
  end

  defp one_snapshot?([first | rest]) do
    Enum.all?(rest, &(&1.snapshot == first.snapshot))
  end

  defp bucket(entries, state), do: Enum.filter(entries, &(&1.state == state))

  defp class_refs(memories, memory_class) do
    memories
    |> Enum.filter(&(&1.memory_class == memory_class))
    |> Enum.map(& &1.memory_ref)
  end

  defp distinct_lifecycle(entries, field) do
    entries
    |> Enum.map(&Map.fetch!(&1, field))
    |> Enum.uniq()
  end

  defp one_index_revision(entries) do
    case entries |> Enum.map(& &1.index_revision) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [revision] -> revision
      _other -> nil
    end
  end

  defp decode_route_id(value) do
    URI.decode_www_form(value)
  rescue
    ArgumentError -> value
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: nil

  defp string_list(values) when is_list(values),
    do: Enum.filter(values, &(is_binary(&1) and &1 != ""))

  defp string_list(_values), do: []
end
