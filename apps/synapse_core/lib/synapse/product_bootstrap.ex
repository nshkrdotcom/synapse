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
  @agent_intake_callbacks [
    start_agent_run: 3,
    submit_agent_turn: 3,
    cancel_agent_run: 3,
    await_agent_outcome: 4,
    catch_up_agent_events: 3,
    list_pending_interactions: 3
  ]
  @headless_callbacks [
    state_snapshot: 3,
    runtime_subject_detail: 4,
    runtime_run_detail: 4,
    request_runtime_refresh: 3,
    request_runtime_control: 3
  ]
  @effect_surface_callbacks [
    propose_effect: 3,
    begin_dispatch: 4,
    record_accepted: 4,
    record_receipt: 4,
    get_effect: 3,
    get_effect_by_idempotency: 3
  ]
  @review_surface_callbacks [
    list_pending: 3,
    get_review: 3,
    record_decision: 4,
    record_decision_by_id: 4
  ]
  @operator_surface_callbacks [
    list_memory_fragments: 3,
    memory_fragment_by_proof_token: 3,
    memory_fragment_provenance: 3
  ]
  @product_surface_callbacks [
    run_projection: 3,
    capability_projections: 3
  ]

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

  @doc """
  Resolves the runtime-injected AppKit backend stack for intake commands.

  Production composition supplies either an `AppKit.BackendStack` directly or
  a provider module exporting `backend_stack/0`. Explicit `:backend` selection
  remains available for deterministic tests, but there is no compiled product
  default and an absent or incomplete runtime stack fails closed.
  """
  @spec agent_intake_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def agent_intake_options(overrides \\ []) do
    opts = configured_backend_options(overrides)

    with {:ok, opts} <- resolve_backend_stack(opts),
         :ok <- validate_owner_routing(opts),
         :ok <- validate_role(opts, :agent_intake_backend, @agent_intake_callbacks) do
      {:ok, opts}
    end
  end

  @doc "Returns backend options only when durable run snapshot and cursor roles are composed."
  @spec durable_readback_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def durable_readback_options(overrides \\ []) do
    with {:ok, opts} <- agent_intake_options(overrides),
         :ok <- validate_role(opts, :headless_backend, @headless_callbacks) do
      {:ok, opts}
    end
  end

  @doc """
  Returns options only when the coherent AppKit product projection is composed.

  Product availability is still decided by the owner-backed projection call;
  this check only proves that the executable AppKit role is present and
  implements the current boundary contract.
  """
  @spec product_surface_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def product_surface_options(overrides \\ []) do
    with {:ok, opts} <- durable_readback_options(overrides),
         :ok <- validate_role(opts, :product_surface_backend, @product_surface_callbacks) do
      {:ok, opts}
    end
  end

  @doc "Returns options only when a current AppKit governed-effect backend is composed."
  @spec effect_surface_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def effect_surface_options(overrides \\ []) do
    opts = configured_backend_options(overrides)

    with {:ok, opts} <- resolve_optional_backend_stack(opts),
         :ok <-
           validate_surface_role(
             opts,
             :effect_surface_adapter,
             :effect_surface_backend,
             @effect_surface_callbacks
           ) do
      {:ok, opts}
    end
  end

  @doc "Returns options only when a current AppKit review backend is composed."
  @spec review_surface_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def review_surface_options(overrides \\ []) do
    opts = configured_backend_options(overrides)

    with {:ok, opts} <- resolve_optional_backend_stack(opts),
         :ok <-
           validate_surface_role(
             opts,
             :review_backend,
             :review_backend,
             @review_surface_callbacks
           ) do
      {:ok, opts}
    end
  end

  @doc "Returns options only when durable product-safe operator memory reads are composed."
  @spec operator_surface_options(keyword() | map()) :: {:ok, keyword()} | {:error, atom()}
  def operator_surface_options(overrides \\ []) do
    opts = configured_backend_options(overrides)

    with {:ok, opts} <- resolve_optional_backend_stack(opts),
         :ok <-
           validate_surface_role(
             opts,
             :operator_backend,
             :operator_backend,
             @operator_surface_callbacks
           ) do
      {:ok, opts}
    end
  end

  @spec effect_surface_status(keyword() | map()) :: map()
  def effect_surface_status(overrides \\ []) do
    opts = configured_backend_options(overrides)
    effect_surface_loaded? = effect_surface_loaded?()
    review_surface_loaded? = review_surface_loaded?()
    effect_backend_available? = match?({:ok, _opts}, effect_surface_options(opts))
    review_backend_available? = match?({:ok, _opts}, review_surface_options(opts))
    agent_intake_available? = agent_intake_available?(opts)

    live? =
      effect_surface_loaded? and review_surface_loaded? and effect_backend_available? and
        review_backend_available? and agent_intake_available?

    %{
      status: if(live?, do: :staging_live, else: :unavailable),
      surface: "AppKit.EffectSurface",
      live?: live?,
      effect_surface_available?: effect_surface_loaded? and effect_backend_available?,
      review_surface_available?: review_surface_loaded? and review_backend_available?,
      agent_intake_available?: agent_intake_available?,
      mode: :reviewed_file_effect
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
      function_exported?(AppKit.EffectSurface, :begin_dispatch, 4) and
      function_exported?(AppKit.EffectSurface, :record_accepted, 4) and
      function_exported?(AppKit.EffectSurface, :record_receipt, 4) and
      function_exported?(AppKit.EffectSurface, :get_effect, 3) and
      function_exported?(AppKit.EffectSurface, :get_effect_by_idempotency, 3)
  end

  defp review_surface_loaded? do
    Code.ensure_loaded?(AppKit.ReviewSurface) and
      function_exported?(AppKit.ReviewSurface, :list_pending, 3) and
      function_exported?(AppKit.ReviewSurface, :get_review, 3) and
      function_exported?(AppKit.ReviewSurface, :record_decision, 4) and
      function_exported?(AppKit.ReviewSurface, :record_decision_by_id, 4)
  end

  defp agent_intake_available?(opts) do
    match?({:ok, _opts}, agent_intake_options(opts))
  end

  defp configured_backend_options(overrides) do
    configured = Application.get_env(:synapse_core, :app_kit_backend_options, [])

    configured
    |> backend_options()
    |> Keyword.merge(backend_options(overrides))
  end

  defp resolve_backend_stack(opts) do
    cond do
      Keyword.has_key?(opts, :backend) ->
        {:ok, opts}

      Keyword.has_key?(opts, :agent_intake_backend) ->
        {:ok, Keyword.put(opts, :backend, Keyword.fetch!(opts, :agent_intake_backend))}

      Keyword.has_key?(opts, :backend_stack) ->
        validate_stack_option(opts, :backend_stack)

      Keyword.has_key?(opts, :app_kit_backend_stack) ->
        validate_stack_option(opts, :app_kit_backend_stack)

      true ->
        case Application.fetch_env(:synapse_core, :app_kit_backend_stack) do
          {:ok, configured} -> put_configured_stack(opts, configured)
          :error -> {:error, :app_kit_backend_unavailable}
        end
    end
  end

  defp resolve_optional_backend_stack(opts) do
    if Keyword.has_key?(opts, :backend_stack) or
         Keyword.has_key?(opts, :app_kit_backend_stack) do
      {:ok, opts}
    else
      case Application.fetch_env(:synapse_core, :app_kit_backend_stack) do
        {:ok, configured} -> put_configured_stack(opts, configured)
        :error -> {:ok, opts}
      end
    end
  end

  defp validate_stack_option(opts, key) do
    case Keyword.fetch!(opts, key) do
      %AppKit.BackendStack{} -> {:ok, opts}
      _other -> {:error, :invalid_app_kit_backend_stack}
    end
  end

  defp put_configured_stack(opts, %AppKit.BackendStack{} = stack),
    do: {:ok, Keyword.put(opts, :app_kit_backend_stack, stack)}

  defp put_configured_stack(opts, provider) when is_atom(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :backend_stack, 0) do
      case apply(provider, :backend_stack, []) do
        %AppKit.BackendStack{} = stack ->
          {:ok, Keyword.put(opts, :app_kit_backend_stack, stack)}

        _other ->
          {:error, :invalid_app_kit_backend_stack}
      end
    else
      {:error, :app_kit_backend_unavailable}
    end
  rescue
    _error -> {:error, :app_kit_backend_unavailable}
  catch
    _kind, _reason -> {:error, :app_kit_backend_unavailable}
  end

  defp put_configured_stack(_opts, _configured),
    do: {:error, :invalid_app_kit_backend_stack}

  defp validate_role(opts, role, callbacks) do
    with {:ok, backend} <- backend_for_role(opts, role),
         true <- backend_exports?(backend, callbacks) do
      :ok
    else
      _other -> {:error, :app_kit_backend_unavailable}
    end
  end

  defp validate_surface_role(opts, explicit_key, stack_role, callbacks) do
    backend =
      case Keyword.fetch(opts, explicit_key) do
        {:ok, configured} -> {:ok, configured}
        :error -> stack_role(opts, stack_role)
      end

    with {:ok, backend} <- backend,
         true <- backend_exports?(backend, callbacks) do
      :ok
    else
      _other -> {:error, :app_kit_backend_unavailable}
    end
  end

  defp validate_owner_routing(opts) do
    if present_binary?(Keyword.get(opts, :program_id)) and
         present_binary?(Keyword.get(opts, :work_class_id)) do
      :ok
    else
      {:error, :app_kit_routing_unavailable}
    end
  end

  defp present_binary?(value), do: is_binary(value) and String.trim(value) != ""

  defp backend_for_role(opts, :agent_intake_backend) do
    case Keyword.fetch(opts, :backend) do
      {:ok, backend} -> {:ok, backend}
      :error -> stack_role(opts, :agent_intake_backend)
    end
  end

  defp backend_for_role(opts, role), do: stack_role(opts, role)

  defp stack_role(opts, role) do
    opts
    |> backend_stacks()
    |> Enum.reduce_while(:error, fn stack, :error ->
      case AppKit.BackendStack.fetch(stack, role) do
        {:ok, nil} -> {:cont, :error}
        {:ok, backend} -> {:halt, {:ok, backend}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp backend_exports?(backend, callbacks) when is_atom(backend) do
    Code.ensure_loaded?(backend) and
      Enum.all?(callbacks, fn {function, arity} ->
        function_exported?(backend, function, arity)
      end)
  end

  defp backend_exports?(_backend, _callbacks), do: false

  defp backend_stacks(opts) do
    [
      Keyword.get(opts, :backend_stack),
      Keyword.get(opts, :app_kit_backend_stack)
    ]
    |> Enum.filter(&match?(%AppKit.BackendStack{}, &1))
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
