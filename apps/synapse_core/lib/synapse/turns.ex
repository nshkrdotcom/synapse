defmodule Synapse.Turns do
  @moduledoc """
  Product-safe turn submission over AppKit AgentIntake.
  """

  alias AppKit.AgentIntake
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

  @actor_ref "actor:synapse:operator"
  @default_agent_backend Synapse.Fixtures.AgentIntakeBackend
  @allowed_kinds %{
    "user_input" => :user_input,
    "approval" => :approval,
    "denial" => :denial,
    "replan_hint" => :replan_hint,
    "rework_hint" => :rework_hint,
    "cancel" => :cancel
  }

  @spec submit_turn(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def submit_turn(run_ref_or_id, attrs, opts \\ [])
      when is_binary(run_ref_or_id) and is_map(attrs) and is_list(opts) do
    config = Config.load(opts)

    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    context = PlatformContext.product_context(config, bootstrap.installation_ref, opts)
    run_ref = normalize_run_ref(run_ref_or_id)

    with {:ok, kind} <- turn_kind(attrs),
         {:ok, payload_ref} <- payload_ref(attrs, run_ref) do
      submission = %{
        idempotency_key: "synapse:turn:#{kind}:#{run_ref}",
        actor_ref: @actor_ref,
        run_ref: run_ref,
        kind: kind,
        payload_ref: payload_ref,
        params: %{
          input_summary: string_value(attrs, :input_summary, "Operator turn submitted"),
          source: "synapse_web"
        }
      }

      AgentIntake.submit_turn(context, submission, agent_opts(opts))
    end
  end

  defp turn_kind(attrs) do
    case map_value(attrs, :kind) || "user_input" do
      kind
      when is_atom(kind) and
             kind in [:user_input, :approval, :denial, :replan_hint, :rework_hint, :cancel] ->
        {:ok, kind}

      kind when is_binary(kind) ->
        case Map.fetch(@allowed_kinds, kind) do
          {:ok, kind} -> {:ok, kind}
          :error -> {:error, :invalid_turn_kind}
        end

      _other ->
        {:error, :invalid_turn_kind}
    end
  end

  defp payload_ref(attrs, run_ref) do
    case map_value(attrs, :payload_ref) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:ok, "payload://synapse/turn/#{run_token(run_ref)}"}
    end
  end

  defp normalize_run_ref("run://" <> _rest = ref), do: ref
  defp normalize_run_ref(id), do: "run://fixture/#{id}"
  defp run_token(run_ref), do: run_ref |> String.split("/", trim: true) |> List.last()
  defp agent_opts(opts), do: Keyword.put_new(opts, :backend, @default_agent_backend)

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
