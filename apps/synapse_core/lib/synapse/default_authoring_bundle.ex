defmodule Synapse.DefaultAuthoringBundle do
  @moduledoc """
  Builds the default NSHKR Agent authoring-bundle import envelope.
  """

  alias AppKit.Core.{AuthoringBundleImport, InstallationRef}
  alias Synapse.{Config, ProductInstallTemplate, ProductPack}

  @policy_refs ["synapse.agent_workspace.v1"]

  @spec build(Config.t() | keyword() | map(), InstallationRef.t() | keyword()) ::
          {:ok, AuthoringBundleImport.t()} | {:error, term()}
  def build(config_or_overrides, opts \\ [])

  def build(%Config{} = config, %InstallationRef{} = installation_ref) do
    build(config, installation_ref: installation_ref)
  end

  def build(%Config{} = config, opts) when is_list(opts) do
    manifest_payload = ProductPack.manifest(config) |> dump()
    attrs = unsigned_attrs(config, manifest_payload, opts)
    attrs = Map.put(attrs, "checksum", AuthoringBundleImport.checksum_for(attrs))
    AuthoringBundleImport.new(attrs)
  end

  def build(overrides, opts), do: overrides |> Config.load() |> build(opts)

  @spec default_installation_id(Config.t() | keyword() | map()) :: String.t()
  def default_installation_id(overrides \\ [])

  def default_installation_id(%Config{} = config), do: config.default_installation_id

  def default_installation_id(overrides),
    do: overrides |> Config.load() |> default_installation_id()

  defp unsigned_attrs(%Config{} = config, manifest_payload, opts) do
    install_template = ProductInstallTemplate.default(config)

    %{
      "bundle_id" => bundle_id(config),
      "tenant_id" => config.tenant_id,
      "installation_id" => installation_id(config, opts),
      "pack_manifest" => manifest_payload,
      "lifecycle_specs" => manifest_payload["lifecycle_specs"],
      "decision_specs" => manifest_payload["decision_specs"],
      "binding_descriptors" => install_template.default_bindings,
      "observer_descriptors" => [],
      "context_adapter_descriptors" => [],
      "policy_refs" => @policy_refs,
      "authored_by" => "operator:synapse",
      "expected_installation_revision" => expected_installation_revision(opts),
      "metadata" => %{
        "policy_authority" => "authoring_bundle_installation_revision",
        "product_pack_role" => "seed",
        "runtime_policy_owner" => "authoring_bundle"
      }
    }
  end

  defp bundle_id(%Config{} = config), do: "#{config.product_slug}-default-#{config.pack_version}"

  defp installation_id(%Config{} = config, opts) do
    case Keyword.get(opts, :installation_ref) do
      %InstallationRef{id: id} when is_binary(id) and id != "" -> id
      _other -> Keyword.get(opts, :installation_id, config.default_installation_id)
    end
  end

  defp expected_installation_revision(opts) do
    case Keyword.fetch(opts, :expected_installation_revision) do
      {:ok, revision} ->
        revision

      :error ->
        case Keyword.get(opts, :installation_ref) do
          %InstallationRef{compiled_pack_revision: revision} -> revision
          _other -> nil
        end
    end
  end

  defp dump(%{__struct__: _module} = value) do
    value
    |> Map.from_struct()
    |> dump()
  end

  defp dump(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {dump_key(key), dump(nested)} end)
  end

  defp dump(value) when is_list(value), do: Enum.map(value, &dump/1)
  defp dump(value) when is_atom(value), do: Atom.to_string(value)
  defp dump(value), do: value

  defp dump_key(key) when is_atom(key), do: Atom.to_string(key)
  defp dump_key(key), do: key
end
