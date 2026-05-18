defmodule Synapse.ProductInstallTemplate do
  @moduledoc """
  Product-owned default installation template for NSHKR Agent.
  """

  alias AppKit.Core.InstallTemplate
  alias Synapse.{Config, ProductPack, ProductProfile}

  @spec default(Config.t() | keyword() | map()) :: InstallTemplate.t()
  def default(%Config{} = config) do
    attrs = %{
      template_key: template_key(config),
      pack_slug: ProductPack.pack_slug(config),
      pack_version: ProductPack.pack_version(config),
      default_bindings: default_bindings(config),
      metadata: metadata(config)
    }

    case InstallTemplate.new(attrs) do
      {:ok, template} -> template
      {:error, reason} -> raise ArgumentError, "invalid install template: #{inspect(reason)}"
    end
  end

  def default(overrides), do: overrides |> Config.load() |> default()

  @spec template_key(Config.t() | keyword() | map()) :: String.t()
  def template_key(%Config{} = config), do: "#{config.product_slug}:default"
  def template_key(overrides), do: overrides |> Config.load() |> template_key()

  @spec default_bindings(Config.t()) :: map()
  def default_bindings(%Config{} = config) do
    %{
      "execution_bindings" => %{
        ProductPack.runtime_binding_key(config) => %{
          "runtime_profile_ref" => "multi_agent_runtime_v1",
          "placement_ref" => "platform_default",
          "authority_decision_ref" => "authority-decision://#{config.product_slug}/default",
          "connector_binding_ref" => "connector-binding://agent-loop-runtime",
          "credential_posture_ref" => "no-credentials://#{config.product_slug}/default",
          "execution_params" => %{"timeout_ms" => config.execution_timeout_ms}
        }
      },
      "source_bindings" => %{
        ProductPack.source_binding_key(config) => %{
          "source_class" => "operator_intake",
          "connection_ref" => "product_session"
        }
      },
      "publication_bindings" => %{
        ProductPack.publication_binding_key(config) => %{
          "publication_profile_ref" => "operator_progress_v1",
          "idempotency_scope" => "subject"
        }
      },
      "role_defaults" =>
        ProductProfile.roles()
        |> Map.new(fn role ->
          {role.ref,
           %{
             "model_profile_ref" => role.model_profile_ref,
             "context_policy_ref" => role.context_policy_ref,
             "budget_class" => role.budget_class,
             "failure_posture" => role.failure_posture
           }}
        end)
    }
  end

  defp metadata(%Config{} = config) do
    %{
      "managed_by" => "synapse_core",
      "product_family" => config.product_family,
      "profile" => "default",
      "team_templates" =>
        Enum.map(ProductProfile.team_templates(), fn template ->
          %{
            "ref" => template.ref,
            "display_name" => template.display_name,
            "role_refs" => template.role_refs,
            "execution_posture" => template.execution_posture
          }
        end)
    }
  end
end
