defmodule Synapse.Catalog do
  @moduledoc """
  Truthful product capability catalog projected through `AppKit.ProductSurface`.

  The runtime owner decides which capabilities are executable. Synapse only
  presents AppKit-validated projections and never turns an unavailable or
  degraded descriptor into an advertised product action.
  """

  alias AppKit.Core.ProductSurface.{Availability, CapabilityProjection}
  alias AppKit.ProductSurface
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @raw_keys [
    :api_key,
    :auth_header,
    :body,
    :credential,
    :credentials,
    :payload,
    :provider_payload,
    :raw_body,
    :raw_payload,
    :secret,
    :token,
    "api_key",
    "auth_header",
    "body",
    "credential",
    "credentials",
    "payload",
    "provider_payload",
    "raw_body",
    "raw_payload",
    "secret",
    "token"
  ]

  @spec catalog(keyword()) :: map()
  def catalog(opts \\ []) when is_list(opts) do
    case capability_projections(opts) do
      {:ok, projections} ->
        {advertised, unavailable} =
          Enum.split_with(projections, &advertised_and_available?/1)

        %{
          availability: availability(:available),
          status: :available,
          entries: Enum.map(advertised, &entry/1),
          capabilities: advertised,
          unavailable_capabilities: unavailable,
          hidden_count: length(unavailable),
          source: "AppKit.ProductSurface"
        }

      {:error, reason} ->
        %{
          availability: unavailable(reason),
          status: :unavailable,
          entries: [],
          capabilities: [],
          unavailable_capabilities: [],
          hidden_count: 0,
          source: "AppKit.ProductSurface"
        }
    end
  end

  @spec list_entries(keyword()) :: [map()]
  def list_entries(opts \\ []) when is_list(opts), do: catalog(opts).entries

  @spec get_eligibility(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_eligibility(id_or_ref, opts \\ [])

  def get_eligibility(id_or_ref, opts) when is_binary(id_or_ref) and is_list(opts) do
    catalog = catalog(opts)

    case Enum.find(catalog.entries, &(&1.id == id_or_ref or &1.ref == id_or_ref)) do
      nil ->
        if catalog.status == :available,
          do: {:error, :catalog_eligibility_not_found},
          else: {:error, :capability_catalog_unavailable}

      item ->
        {:ok,
         %{
           item: item,
           projection: item.projection,
           availability: item.projection.availability,
           source: catalog.source
         }}
    end
  end

  def get_eligibility(_id_or_ref, _opts), do: {:error, :invalid_catalog_eligibility_ref}

  @spec assignment_status() :: map()
  def assignment_status do
    %{
      availability: availability({:unavailable, :not_supported}),
      status: :unavailable,
      reason: :not_supported
    }
  end

  @spec reject_raw_payload(map()) :: :ok | {:error, term()}
  def reject_raw_payload(attrs) when is_map(attrs) do
    case Enum.find(@raw_keys, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:raw_catalog_payload_forbidden, key}}
    end
  end

  @spec capability_projections(keyword()) ::
          {:ok, [CapabilityProjection.t()]} | {:error, term()}
  def capability_projections(opts \\ []) when is_list(opts) do
    with {:ok, context, surface_opts} <- product_surface_context(opts),
         {:ok, projections} <-
           safe_capabilities(context, capability_request(opts), surface_opts) do
      {:ok, projections}
    end
  end

  defp product_surface_context(opts) do
    config = Config.load(opts)

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)),
         {:ok, surface_opts} <- ProductBootstrap.durable_readback_options(opts) do
      context = PlatformContext.product_context(config, bootstrap.installation_ref, opts)
      {:ok, context, surface_opts}
    end
  end

  defp capability_request(opts) do
    opts
    |> Keyword.take([:kind, :configured_mode, :scope_ref])
    |> Map.new()
  end

  defp safe_capabilities(context, request, surface_opts) do
    ProductSurface.capabilities(context, request, surface_opts)
  rescue
    _error -> {:error, :product_surface_backend_unavailable}
  catch
    _kind, _reason -> {:error, :product_surface_backend_unavailable}
  end

  defp advertised_and_available?(%CapabilityProjection{
         advertised?: true,
         availability: %Availability{state: :available},
         operation_refs: [_ | _]
       }),
       do: true

  defp advertised_and_available?(_projection), do: false

  defp entry(%CapabilityProjection{} = projection) do
    %{
      id: route_id(projection.capability_ref),
      ref: projection.capability_ref,
      title: projection.capability_ref,
      kind: projection.kind,
      status: :available,
      configured_mode: projection.configured_mode,
      contract_version: projection.contract_version,
      producer_revision_ref: projection.producer_revision_ref,
      health_ref: projection.health_ref,
      operation_refs: projection.operation_refs,
      scope_refs: projection.scope_refs,
      projection: projection
    }
  end

  defp route_id(ref), do: URI.encode_www_form(ref)

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

  defp availability(value) do
    {:ok, availability} = Availability.new(value)
    availability
  end
end
