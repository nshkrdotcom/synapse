defmodule Synapse.Fixtures.InstallationSurface do
  @moduledoc false

  alias AppKit.Core.{InstallationRef, InstallResult}

  def create_installation(_context, template, _opts) do
    install_result(template, :created, "fixture installation created")
  end

  def import_authoring_bundle(_context, bundle, _opts) do
    {:ok, installation_ref} =
      InstallationRef.new(%{
        id: bundle.installation_id,
        pack_slug: bundle.pack_manifest["pack_slug"],
        pack_version: bundle.pack_manifest["version"],
        compiled_pack_revision: 1,
        status: :active
      })

    InstallResult.new(%{
      installation_ref: installation_ref,
      status: :updated,
      message: "fixture authoring bundle imported",
      metadata: %{bundle: bundle}
    })
  end

  defp install_result(template, status, message) do
    {:ok, installation_ref} =
      InstallationRef.new(%{
        id: "default",
        pack_slug: template.pack_slug,
        pack_version: template.pack_version,
        compiled_pack_revision: 1,
        status: :active
      })

    InstallResult.new(%{
      installation_ref: installation_ref,
      status: status,
      message: message,
      metadata: %{template: template}
    })
  end
end
