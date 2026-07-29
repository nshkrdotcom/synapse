defmodule Synapse.Memory.Lifecycle do
  @moduledoc """
  Product-safe lifecycle state reported by the configured AppKit owner.

  A `:not_projected` value is intentional: Synapse does not infer retention,
  deletion, or index facts from a fragment's continued visibility.
  """

  @enforce_keys [:retention_state, :deletion_state, :reindex_state]
  defstruct @enforce_keys ++
              [
                :retention_policy_ref,
                :retention_reason,
                :deleted_at,
                :deletion_reason,
                :index_revision,
                :reindex_reason
              ]

  @type t :: %__MODULE__{}
end

defmodule Synapse.Memory.SnapshotIdentity do
  @moduledoc "Immutable AppKit proof and ordering identity for one retrieval result."

  @enforce_keys [:proof_token_ref, :proof_hash, :snapshot_epoch, :commit_lsn]
  defstruct @enforce_keys ++ [:retrieval_snapshot_ref]

  @type t :: %__MODULE__{}
end

defmodule Synapse.Memory.Entry do
  @moduledoc "Refs-only product projection of one AppKit memory fragment."

  @enforce_keys [
    :id,
    :state,
    :title,
    :memory_ref,
    :memory_class,
    :proof_token_ref,
    :content_hash,
    :redaction_policy_ref,
    :reason_codes,
    :snapshot,
    :lifecycle,
    :projection
  ]
  defstruct @enforce_keys ++
              [
                :evidence_ref,
                :provenance,
                :provenance_label,
                :provenance_projection,
                :content_artifact_ref,
                :content_digest,
                :recorded_at,
                redacted_excerpt: nil,
                feature_status: :durable_readback
              ]

  @type t :: %__MODULE__{}
end

defmodule Synapse.Memory do
  @moduledoc """
  Product-safe durable memory projections read through AppKit.

  Synapse never stores memory truth or dereferences fragment bodies. The
  operator proof token selects an immutable lower retrieval snapshot and only
  AppKit's allowlisted fragment/provenance DTOs cross the product boundary.
  """

  alias AppKit.Core.{
    MemoryFragmentListRequest,
    MemoryFragmentProjection,
    MemoryFragmentProvenance
  }

  alias AppKit.OperatorSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap}
  alias Synapse.Memory.{Entry, Lifecycle, SnapshotIdentity}

  @raw_keys [
    :body,
    :raw_body,
    :payload,
    :raw_payload,
    "body",
    "raw_body",
    "payload",
    "raw_payload"
  ]

  @spec list_memories(keyword()) :: {:ok, [Entry.t()]} | {:error, term()}
  def list_memories(opts \\ []) when is_list(opts) do
    with {:ok, context, runtime_opts} <- operator_context(opts),
         {:ok, proof_token_ref} <- proof_token_ref(runtime_opts),
         {:ok, request} <-
           MemoryFragmentListRequest.new(%{
             proof_token_ref: proof_token_ref,
             include_provenance?: true,
             metadata: %{product_surface: "synapse_memory"}
           }),
         {:ok, fragments} <-
           OperatorSurface.list_memory_fragments(context, request, runtime_opts),
         true <- Enum.all?(fragments, &match?(%MemoryFragmentProjection{}, &1)) do
      {:ok, Enum.map(fragments, &projection_view/1)}
    else
      false -> {:error, :invalid_memory_fragment_projection}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_memory(String.t(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def get_memory(id_or_ref, opts \\ []) when is_binary(id_or_ref) and is_list(opts) do
    decoded_id = decode_route_id(id_or_ref)

    with {:ok, memories} <- list_memories(opts),
         %{} = memory <-
           Enum.find(memories, fn memory ->
             memory.id in [id_or_ref, decoded_id] or
               memory.memory_ref in [id_or_ref, decoded_id]
           end),
         {:ok, provenance} <- memory_provenance(memory.memory_ref, opts) do
      {:ok, %{memory | provenance_projection: provenance}}
    else
      nil -> {:error, :memory_projection_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec write_feedback(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def write_feedback(attrs, _opts \\ []) when is_map(attrs) do
    with :ok <- reject_raw_payload(attrs) do
      {:error, :memory_feedback_write_not_in_current_journey}
    end
  end

  @spec feedback_status() :: map()
  def feedback_status do
    %{
      status: :disabled,
      reason: :memory_feedback_write_not_in_current_journey,
      required_surface: "AppKit governed memory mutation"
    }
  end

  @spec surface_status(keyword()) :: map()
  def surface_status(opts \\ []) when is_list(opts) do
    with {:ok, runtime_opts} <- ProductBootstrap.operator_surface_options(opts),
         {:ok, proof_token_ref} <- proof_token_ref(runtime_opts) do
      %{
        status: :durable_readback,
        public_surface: "AppKit.OperatorSurface",
        proof_token_ref: proof_token_ref
      }
    else
      {:error, reason} ->
        %{status: :unavailable, public_surface: "AppKit.OperatorSurface", reason: reason}
    end
  end

  defp memory_provenance(fragment_ref, opts) do
    with {:ok, context, runtime_opts} <- operator_context(opts),
         {:ok, %MemoryFragmentProvenance{} = provenance} <-
           OperatorSurface.memory_fragment_provenance(context, fragment_ref, runtime_opts) do
      {:ok, provenance}
    else
      {:ok, _other} -> {:error, :invalid_memory_fragment_provenance}
      {:error, reason} -> {:error, reason}
    end
  end

  defp operator_context(opts) do
    config = Config.load(opts)

    with {:ok, runtime_opts} <- ProductBootstrap.operator_surface_options(opts),
         {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)) do
      context_opts =
        runtime_opts
        |> Keyword.take([:trace_id, :correlation_id, :request_id, :idempotency_key])
        |> Keyword.merge(opts)

      {:ok, PlatformContext.product_context(config, bootstrap.installation_ref, context_opts),
       runtime_opts}
    end
  end

  defp proof_token_ref(opts) do
    case Keyword.get(opts, :memory_proof_token_ref) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :memory_proof_token_unavailable}
    end
  end

  defp projection_view(%MemoryFragmentProjection{} = projection) do
    state = memory_state(projection)
    metadata = projection.metadata || %{}

    %Entry{
      id: route_id(projection.fragment_ref),
      state: state,
      title: metadata_value(metadata, :title) || projection.fragment_ref,
      memory_ref: projection.fragment_ref,
      memory_class: memory_class(projection.tier),
      proof_token_ref: projection.proof_token_ref,
      evidence_ref: List.first(projection.evidence_refs),
      content_hash: projection.proof_hash,
      redaction_policy_ref: projection.redaction_posture,
      provenance: List.first(projection.provenance_refs),
      provenance_label: provenance_label(List.first(projection.provenance_refs)),
      reason_codes: reason_codes(projection, state),
      snapshot: snapshot_identity(projection, metadata),
      lifecycle: lifecycle(projection, metadata),
      content_artifact_ref: optional_string(metadata_value(metadata, :content_artifact_ref)),
      content_digest: optional_string(metadata_value(metadata, :content_digest)),
      recorded_at: optional_string(metadata_value(metadata, :recorded_at)),
      projection: projection
    }
  end

  defp snapshot_identity(projection, metadata) do
    %SnapshotIdentity{
      proof_token_ref: projection.proof_token_ref,
      proof_hash: projection.proof_hash,
      snapshot_epoch: projection.snapshot_epoch,
      commit_lsn: projection.commit_lsn,
      retrieval_snapshot_ref: optional_string(metadata_value(metadata, :retrieval_snapshot_ref))
    }
  end

  defp lifecycle(projection, metadata) do
    {retention_state, retention_reason} = retention_state(metadata)
    {deletion_state, deletion_reason} = deletion_state(projection, metadata)
    {reindex_state, reindex_reason} = reindex_state(metadata)

    %Lifecycle{
      retention_state: retention_state,
      retention_policy_ref: optional_string(metadata_value(metadata, :retention_policy_ref)),
      retention_reason: retention_reason,
      deletion_state: deletion_state,
      deleted_at: optional_string(metadata_value(metadata, :deleted_at)),
      deletion_reason: deletion_reason,
      reindex_state: reindex_state,
      index_revision: positive_integer(metadata_value(metadata, :index_revision)),
      reindex_reason: reindex_reason
    }
  end

  defp retention_state(metadata) do
    case metadata_value(metadata, :retention_state) do
      value when value in ["retained", :retained] -> {:retained, nil}
      value when value in ["expired", :expired] -> {:expired, nil}
      value when value in ["deleted", :deleted] -> {:deleted, nil}
      value when value in ["legal_hold", :legal_hold] -> {:legal_hold, nil}
      _other -> {:not_projected, "retention_state_not_projected"}
    end
  end

  defp deletion_state(projection, metadata) do
    reason = optional_string(metadata_value(metadata, :deletion_reason))

    case metadata_value(metadata, :deletion_state) do
      value when value in ["active", :active] ->
        {:active, reason}

      value when value in ["deleted", :deleted] ->
        {:deleted, reason}

      value when value in ["tombstoned", :tombstoned] ->
        {:tombstoned, reason}

      value when value in ["retention_expired", :retention_expired] ->
        {:retention_expired, reason}

      _other ->
        deletion_state_from_invalidation(projection.cluster_invalidation_status)
    end
  end

  defp deletion_state_from_invalidation("revoked"),
    do: {:revoked, "exact_deletion_fact_not_projected"}

  defp deletion_state_from_invalidation(status)
       when status in ["pending", "reconciling"],
       do: {:pending, status}

  defp deletion_state_from_invalidation("unknown"),
    do: {:unknown, "deletion_state_unknown"}

  defp deletion_state_from_invalidation(_status),
    do: {:not_projected, "deletion_state_not_projected"}

  defp reindex_state(metadata) do
    revision = positive_integer(metadata_value(metadata, :index_revision))

    case metadata_value(metadata, :reindex_state) do
      value when value in ["indexed", :indexed] -> {:indexed, nil}
      value when value in ["pending", :pending] -> {:pending, nil}
      value when value in ["rebuilding", :rebuilding] -> {:rebuilding, nil}
      value when value in ["degraded", :degraded] -> {:degraded, nil}
      _other when is_integer(revision) -> {:indexed, nil}
      _other -> {:not_projected, "index_revision_not_projected"}
    end
  end

  defp memory_class("working"), do: :working
  defp memory_class(:working), do: :working
  defp memory_class("episodic"), do: :episodic
  defp memory_class(:episodic), do: :episodic
  defp memory_class(_other), do: :unsupported

  defp provenance_label(value) when is_binary(value), do: value

  defp provenance_label(value) when is_map(value) do
    optional_string(metadata_value(value, :source_ref)) ||
      optional_string(metadata_value(value, :recording_operation_ref)) ||
      optional_string(metadata_value(value, :authority_ref)) ||
      "owner-projected provenance"
  end

  defp provenance_label(_value), do: nil

  defp memory_state(%MemoryFragmentProjection{cluster_invalidation_status: "revoked"}),
    do: :revoked

  defp memory_state(%MemoryFragmentProjection{} = projection) do
    case metadata_value(projection.metadata || %{}, :state) do
      state when state in ["candidate", :candidate] -> :candidate
      _other -> staleness_state(projection.staleness_class)
    end
  end

  defp staleness_state(staleness_class)
       when staleness_class in ["invalidation_pending", "invalidation_reconciling"],
       do: :stale

  defp staleness_state(staleness_class)
       when staleness_class in ["partitioned", "unknown"],
       do: :degraded

  defp staleness_state(_staleness_class), do: :included

  defp reason_codes(projection, state) do
    metadata_codes =
      case metadata_value(projection.metadata || %{}, :reason_codes) do
        values when is_list(values) -> Enum.filter(values, &is_binary/1)
        _other -> []
      end

    [
      if(projection.cluster_invalidation_status != "none",
        do: projection.cluster_invalidation_status
      ),
      if(projection.staleness_class not in ["fresh", "epoch_bounded"],
        do: projection.staleness_class
      ),
      if(state == :candidate, do: "promotion_review_required")
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(metadata_codes)
    |> Enum.uniq()
  end

  defp route_id(fragment_ref), do: URI.encode_www_form(fragment_ref)

  defp decode_route_id(value) do
    URI.decode_www_form(value)
  rescue
    ArgumentError -> value
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: nil

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp reject_raw_payload(attrs) do
    case Enum.find(@raw_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_memory_payload_forbidden, key}}
    end
  end
end
