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

  @spec effect_surface_status(keyword() | map()) :: map()
  def effect_surface_status(overrides \\ []) do
    opts = backend_options(overrides)
    effect_surface_loaded? = effect_surface_loaded?()
    effect_backend_available? = effect_backend_available?(opts)
    agent_intake_available? = agent_intake_available?(opts)
    live? = effect_surface_loaded? and effect_backend_available? and agent_intake_available?

    %{
      status: if(live?, do: :staging_live, else: :fixture_backed),
      surface: "AppKit.EffectSurface",
      live?: live?,
      effect_surface_available?: effect_surface_loaded? and effect_backend_available?,
      agent_intake_available?: agent_intake_available?,
      mode: :diagnostic_lane
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

  defp backend_options(overrides) when is_list(overrides), do: overrides
  defp backend_options(overrides) when is_map(overrides), do: Map.to_list(overrides)

  defp effect_surface_loaded? do
    Code.ensure_loaded?(AppKit.EffectSurface) and
      function_exported?(AppKit.EffectSurface, :propose_effect, 3) and
      function_exported?(AppKit.EffectSurface, :get_effect_timeline, 3)
  end

  defp effect_backend_available?(opts) do
    explicit_backend?(opts, :effect_surface_adapter) or
      stack_backend?(opts, :effect_surface_backend) or default_bridge_effect_backend?()
  end

  defp agent_intake_available?(opts) do
    explicit_backend?(opts, :backend) or
      explicit_backend?(opts, :agent_intake_backend) or
      stack_backend?(opts, :agent_intake_backend) or default_bridge_agent_backend?()
  end

  defp explicit_backend?(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, backend} when is_atom(backend) -> Code.ensure_loaded?(backend)
      {:ok, nil} -> false
      {:ok, _backend} -> true
      :error -> false
    end
  end

  defp stack_backend?(opts, key) do
    opts
    |> backend_stacks()
    |> Enum.any?(fn stack ->
      case AppKit.BackendStack.fetch(stack, key) do
        {:ok, backend} when is_atom(backend) -> Code.ensure_loaded?(backend)
        {:ok, nil} -> false
        {:ok, _backend} -> true
        :error -> false
      end
    end)
  end

  defp backend_stacks(opts) do
    [
      Keyword.get(opts, :backend_stack),
      Keyword.get(opts, :app_kit_backend_stack)
    ]
    |> Enum.filter(&match?(%AppKit.BackendStack{}, &1))
  end

  defp default_bridge_effect_backend? do
    Code.ensure_loaded?(AppKit.Bridges.MezzanineBridge) and
      function_exported?(AppKit.Bridges.MezzanineBridge, :propose_effect, 3)
  end

  defp default_bridge_agent_backend? do
    Code.ensure_loaded?(AppKit.Bridges.MezzanineBridge) and
      function_exported?(AppKit.Bridges.MezzanineBridge, :start_agent_run, 3)
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
