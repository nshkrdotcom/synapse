defmodule Synapse.Config do
  @moduledoc """
  Normalized product-core configuration for the NSHKR Agent product.
  """

  @bootstrap_modes [:required, :retrying, :disabled]

  @defaults %{
    tenant_id: "default",
    product_slug: "nshkr-agent",
    product_name: "NSHKR Agent",
    product_family: "agent_workspace",
    pack_version: "0.1.0",
    default_installation_id: "default",
    bootstrap_mode: :disabled,
    execution_timeout_ms: 300_000,
    operator_surface_enabled?: true
  }

  @enforce_keys [
    :tenant_id,
    :product_slug,
    :product_name,
    :product_family,
    :pack_version,
    :default_installation_id,
    :bootstrap_mode,
    :execution_timeout_ms,
    :operator_surface_enabled?
  ]
  defstruct @enforce_keys

  @type bootstrap_mode :: :required | :retrying | :disabled

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          product_slug: String.t(),
          product_name: String.t(),
          product_family: String.t(),
          pack_version: String.t(),
          default_installation_id: String.t(),
          bootstrap_mode: bootstrap_mode(),
          execution_timeout_ms: pos_integer(),
          operator_surface_enabled?: boolean()
        }

  @spec load(keyword() | map()) :: t()
  def load(overrides \\ []) do
    configured =
      :synapse_core
      |> Application.get_env(__MODULE__, [])
      |> attrs_to_map()
      |> Map.merge(attrs_to_map(overrides))

    %__MODULE__{
      tenant_id: string!(configured, :tenant_id),
      product_slug: string!(configured, :product_slug),
      product_name: string!(configured, :product_name),
      product_family: string!(configured, :product_family),
      pack_version: string!(configured, :pack_version),
      default_installation_id: string!(configured, :default_installation_id),
      bootstrap_mode: bootstrap_mode!(value(configured, :bootstrap_mode)),
      execution_timeout_ms: positive_integer!(configured, :execution_timeout_ms),
      operator_surface_enabled?: boolean!(configured, :operator_surface_enabled?)
    }
  end

  @spec bootstrap_modes() :: [bootstrap_mode()]
  def bootstrap_modes, do: @bootstrap_modes

  defp attrs_to_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_to_map(attrs) when is_map(attrs), do: attrs

  defp string!(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "invalid Synapse.Config #{key}"
    end
  end

  defp positive_integer!(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> raise ArgumentError, "invalid Synapse.Config #{key}"
    end
  end

  defp boolean!(attrs, key) do
    case value(attrs, key) do
      value when is_boolean(value) -> value
      _other -> raise ArgumentError, "invalid Synapse.Config #{key}"
    end
  end

  defp bootstrap_mode!(mode) when mode in @bootstrap_modes, do: mode
  defp bootstrap_mode!("required"), do: :required
  defp bootstrap_mode!("retrying"), do: :retrying
  defp bootstrap_mode!("disabled"), do: :disabled

  defp bootstrap_mode!(mode) do
    raise ArgumentError, "invalid Synapse.Config bootstrap_mode #{inspect(mode)}"
  end

  defp value(attrs, key) do
    string_key = Atom.to_string(key)

    case Map.fetch(attrs, string_key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, key, Map.fetch!(@defaults, key))
    end
  end
end
