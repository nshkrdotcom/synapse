defmodule Synapse.ProductBootstrap do
  @moduledoc """
  Idempotent product bootstrap through the northbound AppKit installation surface.
  """

  alias AppKit.Core.{InstallationRef, InstallResult}

  alias Synapse.{
    Config,
    DefaultAuthoringBundle,
    PlatformContext,
    ProductInstallTemplate,
    ProductPack
  }

  @default_installation_surface AppKit.InstallationSurface
  @retry_delay_ms 2_000

  @spec ensure_bootstrapped(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def ensure_bootstrapped(overrides \\ []) do
    opts = context_options(overrides)
    config = Config.load(overrides)

    case config.bootstrap_mode do
      :disabled -> {:ok, disabled_result(config)}
      :required -> run_bootstrap(config, opts)
      :retrying -> run_or_retry(config, opts)
    end
  end

  @spec fixture_status(keyword() | map()) :: map()
  def fixture_status(overrides \\ []) do
    config = Config.load(overrides)

    %{
      status: :fixture_backed,
      mode: config.bootstrap_mode,
      installation_id: config.default_installation_id,
      pack_slug: ProductPack.pack_slug(config),
      pack_version: ProductPack.pack_version(config),
      surface: "AppKit.InstallationSurface",
      live?: false
    }
  end

  defp run_or_retry(%Config{} = config, opts) do
    case run_bootstrap(config, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:ok,
         config
         |> disabled_result()
         |> Map.merge(%{
           status: :retry_scheduled,
           reason: reason,
           retry_delay_ms: @retry_delay_ms
         })}
    end
  end

  defp run_bootstrap(%Config{} = config, opts) do
    install_template = ProductInstallTemplate.default(config)

    with {:ok, surface} <- installation_surface(opts),
         {:ok, install_result} <- create_installation(surface, config, install_template, opts),
         {:ok, bundle_import} <-
           DefaultAuthoringBundle.build(config, install_result.installation_ref),
         {:ok, bundle_result} <-
           import_authoring_bundle(surface, config, install_result, bundle_import, opts) do
      {:ok,
       %{
         status: :bootstrapped,
         mode: config.bootstrap_mode,
         config: config,
         install_template: install_template,
         install_result: install_result,
         authoring_result: bundle_result,
         installation_ref: bundle_result.installation_ref,
         pack: %{slug: ProductPack.pack_slug(config), version: ProductPack.pack_version(config)},
         routing: PlatformContext.routing_metadata(config)
       }}
    end
  end

  defp create_installation(surface, %Config{} = config, install_template, opts) do
    context = PlatformContext.bootstrap_context(config, opts)
    apply(surface, :create_installation, [context, install_template, opts])
  end

  defp import_authoring_bundle(
         surface,
         %Config{} = config,
         %InstallResult{} = install_result,
         bundle,
         opts
       ) do
    context = PlatformContext.product_context(config, install_result.installation_ref, opts)
    apply(surface, :import_authoring_bundle, [context, bundle, opts])
  end

  defp installation_surface(opts) do
    surface = Keyword.get(opts, :installation_surface, @default_installation_surface)

    cond do
      not is_atom(surface) ->
        {:error, :invalid_installation_surface}

      Code.ensure_loaded?(surface) and
        function_exported?(surface, :create_installation, 3) and
          function_exported?(surface, :import_authoring_bundle, 3) ->
        {:ok, surface}

      true ->
        {:error, {:installation_surface_not_available, surface}}
    end
  end

  defp disabled_result(%Config{} = config) do
    {:ok, installation_ref} =
      InstallationRef.new(%{
        id: config.default_installation_id,
        pack_slug: ProductPack.pack_slug(config),
        pack_version: ProductPack.pack_version(config),
        compiled_pack_revision: 0,
        status: :inactive
      })

    %{
      status: :disabled,
      mode: config.bootstrap_mode,
      installation_ref: installation_ref,
      pack: %{slug: ProductPack.pack_slug(config), version: ProductPack.pack_version(config)},
      routing: PlatformContext.routing_metadata(config)
    }
  end

  defp context_options(overrides) do
    attrs =
      case overrides do
        opts when is_list(opts) -> Map.new(opts)
        opts when is_map(opts) -> opts
      end

    [
      trace_id: first_present(attrs, [:trace_id, "trace_id"]),
      correlation_id:
        first_present(attrs, [:correlation_id, "correlation_id", :causation_id, "causation_id"]),
      request_id: first_present(attrs, [:request_id, "request_id"]),
      idempotency_key: first_present(attrs, [:idempotency_key, "idempotency_key"]),
      installation_id: first_present(attrs, [:installation_id, "installation_id"]),
      profile_ref: first_present(attrs, [:profile_ref, "profile_ref"]),
      role_ref: first_present(attrs, [:role_ref, "role_ref"]),
      team_template_ref: first_present(attrs, [:team_template_ref, "team_template_ref"]),
      installation_surface: first_present(attrs, [:installation_surface, "installation_surface"]),
      live?: truthy?(first_present(attrs, [:live?, "live?", :live, "live"]))
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp first_present(attrs, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(attrs, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp truthy?(value) when value in [true, 1], do: true
  defp truthy?(value) when is_binary(value), do: value in ["true", "1", "yes", "on"]
  defp truthy?(_value), do: false
end
