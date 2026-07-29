defmodule Synapse.Turns do
  @moduledoc """
  Product-safe turn submission over AppKit AgentIntake.
  """

  alias AppKit.AgentIntake
  alias Synapse.{Config, PlatformContext, ProductBootstrap}

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

    with {:ok, bootstrap} <-
           ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled)),
         context <- PlatformContext.product_context(config, bootstrap.installation_ref, opts),
         {:ok, runtime_opts} <- ProductBootstrap.agent_intake_options(opts),
         run_ref <- decode_run_ref(run_ref_or_id),
         {:ok, kind} <- turn_kind(attrs),
         {:ok, submission_token} <- submission_token(attrs, opts),
         submission_identity <- submission_identity(run_ref, kind, submission_token),
         {:ok, payload_ref} <- payload_ref(attrs, submission_identity),
         {:ok, cursor_ref} <- optional_ref(attrs, opts, :cursor_ref),
         {:ok, pending_ref} <- optional_ref(attrs, opts, :pending_ref) do
      dispatch_turn(
        context,
        run_ref,
        kind,
        payload_ref,
        cursor_ref,
        pending_ref,
        submission_identity,
        attrs,
        runtime_opts
      )
    end
  end

  defp dispatch_turn(
         context,
         run_ref,
         :cancel,
         _payload_ref,
         _cursor_ref,
         _pending_ref,
         _submission_identity,
         _attrs,
         runtime_opts
       ) do
    AgentIntake.cancel_agent_run(context, run_ref, runtime_opts)
  end

  defp dispatch_turn(
         context,
         run_ref,
         kind,
         payload_ref,
         cursor_ref,
         pending_ref,
         submission_identity,
         attrs,
         runtime_opts
       ) do
    AgentIntake.submit_turn(
      context,
      %{
        idempotency_key: "synapse:turn:#{kind}:#{submission_identity}",
        actor_ref: context.actor_ref.id,
        run_ref: run_ref,
        kind: kind,
        payload_ref: payload_ref,
        cursor_ref: cursor_ref,
        pending_ref: pending_ref,
        params: %{
          input_summary: string_value(attrs, :input_summary, "Operator turn submitted"),
          source: "synapse_web"
        }
      },
      runtime_opts
    )
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

  defp submission_token(attrs, opts) do
    case Keyword.get(opts, :submission_token) || map_value(attrs, :submission_token) do
      value when is_binary(value) and value != "" -> {:ok, value}
      nil -> {:ok, "turn-#{System.unique_integer([:positive, :monotonic])}"}
      _other -> {:error, :invalid_turn_submission_token}
    end
  end

  defp submission_identity(run_ref, kind, submission_token) do
    :crypto.hash(:sha256, :erlang.term_to_binary({run_ref, kind, submission_token}))
    |> Base.url_encode64(padding: false)
  end

  defp payload_ref(attrs, submission_identity) do
    case map_value(attrs, :payload_ref) do
      value when is_binary(value) and value != "" -> {:ok, value}
      nil -> {:ok, "payload://synapse/turn/#{submission_identity}"}
      _other -> {:error, :invalid_turn_payload_ref}
    end
  end

  defp optional_ref(attrs, opts, key) do
    case Keyword.get(opts, key) || map_value(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      nil -> {:ok, nil}
      _other -> {:error, invalid_optional_ref(key)}
    end
  end

  defp invalid_optional_ref(:cursor_ref), do: :invalid_turn_cursor_ref
  defp invalid_optional_ref(:pending_ref), do: :invalid_turn_pending_ref

  defp decode_run_ref(value) do
    URI.decode_www_form(value)
  rescue
    ArgumentError -> value
  end

  defp string_value(attrs, key, default) do
    case map_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp map_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
