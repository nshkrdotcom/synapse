defmodule Synapse.Evidence do
  @moduledoc """
  Durable artifact, evidence, receipt, and operations readback through AppKit.

  Synapse presents only refs and typed states from an AppKit-validated
  `ProductSurface.RunProjection`. It does not invent evidence for a run event,
  reconstruct receipts, or use replay fixtures when an owner projection is
  absent.
  """

  alias AppKit.Core.{EvidenceProjection, RuntimeEventSummary, RuntimeFactsProjection}
  alias AppKit.Core.ProductSurface.{ArtifactProjection, OperationProjection, RunProjection}
  alias AppKit.Core.RuntimeSurface.RuntimeStatusSnapshot
  alias AppKit.{ProductSurface, RuntimeSurface}
  alias Synapse.{AgentRuns, Config, PlatformContext, ProductBootstrap}

  @spec snapshot(keyword()) :: map()
  def snapshot(opts \\ []) when is_list(opts) do
    case projection_batch(opts) do
      {:ok, projections, failures} ->
        {status, availability} =
          if failures == [] do
            {:available, available()}
          else
            {:degraded, degraded_projection_batch()}
          end

        %{
          status: status,
          availability: availability,
          evidence: evidence_items(projections),
          artifacts: artifact_items(projections),
          projection_error_count: length(failures),
          replay: unavailable_replay(),
          source: "AppKit.ProductSurface"
        }

      {:error, reason} ->
        %{
          status: :unavailable,
          availability: unavailable(reason),
          evidence: [],
          artifacts: [],
          projection_error_count: 0,
          replay: unavailable_replay(),
          source: "AppKit.ProductSurface"
        }
    end
  end

  @spec list_evidence(keyword()) :: [map()]
  def list_evidence(opts \\ []) when is_list(opts), do: snapshot(opts).evidence

  @spec list_artifacts(keyword()) :: [ArtifactProjection.t()]
  def list_artifacts(opts \\ []) when is_list(opts), do: snapshot(opts).artifacts

  @spec get_evidence(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_evidence(id_or_ref, opts \\ [])

  def get_evidence(id_or_ref, opts) when is_binary(id_or_ref) and is_list(opts) do
    surface = snapshot(opts)

    case Enum.find(surface.evidence, &(&1.id == id_or_ref or &1.evidence_ref == id_or_ref)) do
      nil ->
        if surface.status == :available,
          do: {:error, :evidence_not_found},
          else: {:error, :evidence_surface_unavailable}

      item ->
        {:ok, item}
    end
  end

  def get_evidence(_id_or_ref, _opts), do: {:error, :invalid_evidence_ref}

  @spec get_receipt(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_receipt(receipt_ref, opts \\ [])

  def get_receipt(receipt_ref, opts) when is_binary(receipt_ref) and is_list(opts) do
    with {:ok, projections} <- run_projections(opts),
         %OperationProjection{} = operation <-
           projections
           |> Enum.flat_map(& &1.operations)
           |> Enum.find(&(&1.receipt_ref == receipt_ref)) do
      {:ok,
       %{
         id: route_id(receipt_ref),
         receipt_ref: receipt_ref,
         state: operation.state,
         run_ref: operation.run_ref,
         attempt_ref: operation.attempt_ref,
         operation: operation
       }}
    else
      nil -> {:error, :receipt_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_receipt(_receipt_ref, _opts), do: {:error, :invalid_receipt_ref}

  @spec replay_bundle(keyword()) :: map()
  def replay_bundle(_opts \\ []), do: unavailable_replay()

  @spec operations(keyword()) :: map()
  def operations(opts \\ []) when is_list(opts) do
    case projection_batch(opts) do
      {:ok, projections, failures} ->
        {status, availability, runtime_status, health_rows} =
          case runtime_status(opts) do
            {:ok, runtime_status} ->
              if failures == [] do
                {:available, available(), runtime_status, health_rows(runtime_status)}
              else
                {:degraded, degraded_projection_batch(), runtime_status,
                 health_rows(runtime_status)}
              end

            {:error, _reason} ->
              {:degraded, degraded_runtime_status(), nil, []}
          end

        operations = Enum.flat_map(projections, & &1.operations)

        %{
          status: status,
          availability: availability,
          runtime_status: runtime_status,
          health_rows: health_rows,
          operation_rows: operations,
          operator_required:
            Enum.filter(operations, &(&1.state in [:operator_required, :outcome_unknown])),
          capabilities: Enum.flat_map(projections, & &1.capabilities),
          projection_error_count: length(failures),
          source: "AppKit.ProductSurface"
        }

      {:error, reason} ->
        %{
          status: :unavailable,
          availability: unavailable(reason),
          runtime_status: nil,
          health_rows: [],
          operation_rows: [],
          operator_required: [],
          capabilities: [],
          projection_error_count: 0,
          source: "AppKit.ProductSurface"
        }
    end
  end

  @spec runtime_facts(keyword()) :: {:ok, RuntimeFactsProjection.t()} | {:error, term()}
  def runtime_facts(opts \\ []) when is_list(opts) do
    with {:ok, projections} <- run_projections(opts) do
      events = projections |> Enum.flat_map(& &1.events) |> event_summaries()
      operations = Enum.flat_map(projections, & &1.operations)

      RuntimeFactsProjection.new(%{
        token_totals: %{"state" => "not_projected"},
        token_dedupe: %{"state" => "not_projected"},
        rate_limit: %{"state" => "not_projected"},
        retry_queue: [],
        aitrace: %{"state" => "separate_from_operations_health"},
        prompt: %{"state" => "refs_only"},
        semantic: %{
          "operation_count" => length(operations),
          "outcome_unknown_count" => Enum.count(operations, &(&1.state == :outcome_unknown)),
          "operator_required_count" => Enum.count(operations, &(&1.state == :operator_required))
        },
        authority: %{"state" => authority_state(projections)},
        events: events,
        metadata: %{
          "source" => "AppKit.ProductSurface",
          "durable_run_count" => length(projections)
        }
      })
    end
  end

  @spec run_projections(keyword()) :: {:ok, [RunProjection.t()]} | {:error, term()}
  def run_projections(opts \\ []) when is_list(opts) do
    case projection_batch(opts) do
      {:ok, projections, _failures} -> {:ok, projections}
      {:error, reason} -> {:error, reason}
    end
  end

  defp projection_batch(opts) do
    with {:ok, context, surface_opts} <- product_surface_context(opts),
         {:ok, run_refs} <- run_refs(opts) do
      Enum.reduce(run_refs, {[], []}, fn run_ref, {projections, failures} ->
        case safe_run_projection(context, run_ref, surface_opts) do
          {:ok, %RunProjection{} = projection} ->
            {[projection | projections], failures}

          {:error, reason} ->
            {projections, [{run_ref, reason} | failures]}
        end
      end)
      |> then(fn
        {[], failures} when failures != [] ->
          {_run_ref, reason} = List.last(failures)
          {:error, reason}

        {projections, failures} ->
          sorted =
            projections
            |> Enum.reverse()
            |> Enum.sort_by(&{updated_sort_key(&1.updated_at), &1.run_ref}, :desc)

          {:ok, sorted, Enum.reverse(failures)}
      end)
    end
  end

  defp product_surface_context(opts) do
    config = Config.load(opts)

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)),
         {:ok, surface_opts} <- ProductBootstrap.product_surface_options(opts) do
      context = PlatformContext.product_context(config, bootstrap.installation_ref, opts)
      {:ok, context, surface_opts}
    end
  end

  defp run_refs(opts) do
    case Keyword.get(opts, :run_ref) do
      run_ref when is_binary(run_ref) and run_ref != "" ->
        {:ok, [run_ref]}

      nil ->
        with {:ok, runs} <- AgentRuns.list_runs(opts) do
          {:ok, Enum.map(runs, & &1.ref)}
        end

      _other ->
        {:error, :invalid_run_ref}
    end
  end

  defp runtime_status(opts) do
    with {:ok, context, surface_opts} <- product_surface_context(opts) do
      safe_runtime_status(context, surface_opts)
    end
  end

  defp safe_run_projection(context, run_ref, surface_opts) do
    ProductSurface.run_projection(context, run_ref, surface_opts)
  rescue
    _error -> {:error, :product_surface_backend_unavailable}
  catch
    _kind, _reason -> {:error, :product_surface_backend_unavailable}
  end

  defp safe_runtime_status(context, surface_opts) do
    RuntimeSurface.runtime_status(context, %{}, surface_opts)
  rescue
    _error -> {:error, :runtime_surface_backend_unavailable}
  catch
    _kind, _reason -> {:error, :runtime_surface_backend_unavailable}
  end

  defp evidence_items(projections) do
    artifact_evidence =
      Enum.flat_map(projections, fn projection ->
        Enum.flat_map(projection.artifacts, &artifact_evidence_items(&1, projection.run_ref))
      end)

    operation_evidence =
      Enum.flat_map(projections, fn projection ->
        Enum.flat_map(projection.operations, &operation_evidence_items/1)
      end)

    (artifact_evidence ++ operation_evidence)
    |> Enum.uniq_by(& &1.evidence_ref)
    |> Enum.sort_by(& &1.evidence_ref)
  end

  defp artifact_items(projections) do
    projections
    |> Enum.flat_map(& &1.artifacts)
    |> Enum.uniq_by(& &1.artifact_ref)
    |> Enum.sort_by(& &1.artifact_ref)
  end

  defp artifact_evidence_items(%ArtifactProjection{} = artifact, run_ref) do
    Enum.map(artifact.evidence_refs, fn evidence_ref ->
      evidence_item!(
        evidence_ref,
        "artifact_evidence",
        evidence_status(artifact.availability.state),
        artifact.content_ref,
        %{
          "artifact_ref" => artifact.artifact_ref,
          "run_ref" => run_ref,
          "source_contract_ref" => artifact.source_contract_ref
        },
        %{artifact_ref: artifact.artifact_ref, run_ref: run_ref, receipt_ref: nil}
      )
    end)
  end

  defp operation_evidence_items(%OperationProjection{} = operation) do
    Enum.map(operation.evidence_refs, fn evidence_ref ->
      evidence_item!(
        evidence_ref,
        "operation_evidence",
        evidence_status(operation.availability.state),
        nil,
        %{
          "operation_ref" => operation.operation_ref,
          "run_ref" => operation.run_ref,
          "receipt_ref" => operation.receipt_ref,
          "source_contract_ref" => operation.source_contract_ref
        },
        %{
          operation_ref: operation.operation_ref,
          run_ref: operation.run_ref,
          receipt_ref: operation.receipt_ref
        }
      )
    end)
  end

  defp evidence_item!(evidence_ref, kind, status, content_ref, metadata, links) do
    {:ok, projection} =
      EvidenceProjection.new(%{
        evidence_ref: evidence_ref,
        evidence_kind: kind,
        status: status,
        content_ref: content_ref,
        metadata: metadata
      })

    Map.merge(
      %{
        id: route_id(evidence_ref),
        evidence_ref: evidence_ref,
        evidence_kind: kind,
        status: status,
        content_ref: content_ref,
        projection: projection
      },
      links
    )
  end

  defp health_rows(%RuntimeStatusSnapshot{health: health}) do
    health
    |> Enum.map(fn {label, state} ->
      label = to_string(label)

      %{
        id: route_id("health://app-kit/#{label}"),
        label: String.replace(label, "_", " "),
        state: state
      }
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp event_summaries(events) do
    events
    |> Enum.group_by(&to_string(&1.event_kind))
    |> Enum.map(fn {event_kind, rows} ->
      latest = Enum.max_by(rows, & &1.event_seq)

      {:ok, summary} =
        RuntimeEventSummary.new(%{
          event_kind: event_kind,
          count: length(rows),
          latest_event_ref: latest.event_ref
        })

      summary
    end)
    |> Enum.sort_by(& &1.event_kind)
  end

  defp authority_state(projections) do
    if Enum.any?(projections, fn projection ->
         Enum.any?(projection.operations, &(&1.state == :waiting_review))
       end) do
      "review_required"
    else
      "not_projected"
    end
  end

  defp evidence_status(:available), do: "available"
  defp evidence_status(state), do: Atom.to_string(state)

  defp unavailable_replay do
    %{
      status: :unavailable,
      availability: availability({:unavailable, :not_supported}),
      bundle: nil,
      divergences: [],
      replay_links: []
    }
  end

  defp unavailable(reason) do
    reason
    |> unavailable_reason()
    |> then(&availability({:unavailable, &1}))
  end

  defp unavailable_reason(reason)
       when reason in [
              :app_kit_backend_unavailable,
              :app_kit_routing_unavailable,
              :product_surface_backend_unavailable
            ],
       do: :not_configured

  defp unavailable_reason(:not_supported), do: :not_supported
  defp unavailable_reason(_reason), do: :owner_unavailable

  defp available, do: availability(:available)

  defp degraded_projection_batch,
    do: availability({:degraded, "reason://app-kit/partial-run-projection"})

  defp degraded_runtime_status, do: availability({:degraded, "reason://app-kit/runtime-status"})

  defp availability(value) do
    {:ok, availability} = AppKit.Core.ProductSurface.Availability.new(value)
    availability
  end

  defp updated_sort_key(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp updated_sort_key(value), do: to_string(value)

  defp route_id(ref), do: URI.encode_www_form(ref)
end
