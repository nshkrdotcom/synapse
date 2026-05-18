defmodule Synapse.PlatformContext do
  @moduledoc """
  Product-owned request-context helpers for northbound AppKit calls.
  """

  alias AppKit.Core.{InstallationRef, RequestContext}
  alias Synapse.{Config, ProductProfile}

  @actor_ref %{
    id: "synapse_core",
    kind: :system,
    roles: ["product_core"],
    display_name: "Synapse Core"
  }

  @spec bootstrap_context(Config.t(), keyword()) :: RequestContext.t()
  def bootstrap_context(%Config{} = config, opts \\ []) do
    context(config, nil, bootstrap_metadata(config, opts), opts)
  end

  @spec product_context(Config.t(), InstallationRef.t(), keyword()) :: RequestContext.t()
  def product_context(%Config{} = config, %InstallationRef{} = installation_ref, opts \\ []) do
    context(config, installation_ref, product_metadata(config, installation_ref, opts), opts)
  end

  @spec routing_metadata(Config.t()) :: map()
  def routing_metadata(%Config{} = config) do
    %{
      product_slug: config.product_slug,
      product_family: config.product_family,
      pack_version: config.pack_version
    }
  end

  @spec scope_id(Config.t()) :: String.t()
  def scope_id(%Config{} = config), do: "product/#{config.product_slug}"

  defp bootstrap_metadata(%Config{} = config, opts) do
    config
    |> routing_metadata()
    |> Map.put(:runtime_profile, ProductProfile.profile(config))
    |> put_product_boundary_metadata(opts)
  end

  defp product_metadata(%Config{} = config, %InstallationRef{} = installation_ref, opts) do
    config
    |> routing_metadata()
    |> Map.put(:installation_revision, installation_ref.compiled_pack_revision || 1)
    |> Map.put(:product_installation_status, installation_ref.status)
    |> put_product_boundary_metadata(opts)
  end

  defp context(%Config{} = config, installation_ref, metadata, opts) do
    attrs = %{
      trace_id: Keyword.get(opts, :trace_id),
      actor_ref: Keyword.get(opts, :actor_ref, @actor_ref),
      tenant_ref: %{id: config.tenant_id},
      installation_ref: installation_ref,
      causation_id: Keyword.get(opts, :correlation_id) || Keyword.get(opts, :causation_id),
      request_id: Keyword.get(opts, :request_id),
      idempotency_key: Keyword.get(opts, :idempotency_key),
      metadata: metadata
    }

    case RequestContext.new(attrs) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "invalid AppKit context: #{inspect(reason)}"
    end
  end

  defp put_product_boundary_metadata(metadata, opts) do
    boundary =
      opts
      |> Keyword.take([:installation_id, :profile_ref, :role_ref, :team_template_ref, :live?])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    if boundary == %{}, do: metadata, else: Map.put(metadata, :product_boundary_options, boundary)
  end
end
