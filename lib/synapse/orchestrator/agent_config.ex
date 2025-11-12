defmodule Synapse.Orchestrator.AgentConfig do
  @moduledoc """
  Normalized representation of a declarative agent configuration.

  This module provides a strongly-typed struct backed by a NimbleOptions schema so
  configurations can be validated at compile- and boot-time before agents are
  spawned. The resulting struct is used by the orchestrator runtime to drive
  reconciliation and agent creation.
  """

  alias NimbleOptions.ValidationError
  alias Synapse.Signal

  @typedoc "Identifier used to reference an agent across the orchestrator runtime"
  @type agent_id :: atom()

  @typedoc "Archetype supported by the orchestrator"
  @type agent_type :: :specialist | :orchestrator | :custom

  @typedoc "Signal routing patterns"
  @type signal_pattern :: String.t()

  @typedoc "Callable used to build results from action outputs"
  @type result_builder :: function | {module(), atom(), [term()]}

  @typedoc "Callable invoked for custom agents"
  @type custom_handler :: function | {module(), atom(), [term()]}

  @typedoc "Spawn specialists list or strategy"
  @type spawn_specialists :: [agent_id()] | function | {module(), atom(), [term()]}

  @typedoc "Canonical signal topics used by the router"
  @type signal_topic :: Signal.topic()

  @typedoc "Signal configuration normalised by the schema"
  @type signal_config :: %{
          subscribes: [signal_topic()],
          emits: [signal_topic()]
        }

  @typedoc "Orchestrator behaviour configuration"
  @type orchestration :: %{
          classify_fn: function | {module(), atom(), [term()]},
          spawn_specialists: spawn_specialists(),
          aggregation_fn: function | {module(), atom(), [term()]},
          fast_path_fn: function | {module(), atom(), [term()]} | nil
        }

  @typedoc "Complete validated configuration"
  @type t :: %__MODULE__{
          id: agent_id(),
          type: agent_type(),
          signals: signal_config(),
          actions: [module()],
          result_builder: result_builder() | nil,
          custom_handler: custom_handler() | nil,
          orchestration: orchestration() | nil,
          state_schema: keyword() | nil,
          registry: atom() | nil,
          spawn_condition: (-> boolean()) | nil,
          depends_on: [agent_id()],
          metadata: map()
        }

  @enforce_keys [:id, :type, :signals]
  defstruct [
    :id,
    :type,
    :signals,
    :result_builder,
    :custom_handler,
    :orchestration,
    :state_schema,
    :registry,
    :spawn_condition,
    actions: [],
    depends_on: [],
    metadata: %{}
  ]

  @doc """
  Returns the NimbleOptions schema used to validate agent configurations.
  """
  @spec schema() :: NimbleOptions.schema()
  def schema do
    [
      id: [
        type: :atom,
        required: true,
        doc: "Unique identifier for the agent"
      ],
      type: [
        type: {:in, [:specialist, :orchestrator, :custom]},
        required: true,
        doc: "Agent archetype controlling mandatory fields"
      ],
      actions: [
        type: {:list, :atom},
        default: [],
        doc: "List of action modules executed by the agent"
      ],
      signals: [
        type: {:custom, __MODULE__, :validate_signals, []},
        required: true,
        doc: "Signal subscription and emission configuration (router topics)"
      ],
      result_builder: [
        type: {:or, [{:fun, 2}, {:fun, 3}, :mfa]},
        doc: "Callable that converts action outputs into an emitted signal payload"
      ],
      orchestration: [
        type: {:custom, __MODULE__, :validate_orchestration, []},
        doc: "Coordinator-specific behaviour configuration"
      ],
      custom_handler: [
        type: {:or, [{:fun, 2}, :mfa]},
        doc: "Custom callback used by :custom agents"
      ],
      state_schema: [
        type: :keyword_list,
        doc: "NimbleOptions schema describing persistent agent state"
      ],
      registry: [
        type: :atom,
        doc: "Registry used to register running agent processes"
      ],
      spawn_condition: [
        type: {:fun, 0},
        doc: "Predicate to decide if the agent should run based on runtime state"
      ],
      depends_on: [
        type: {:list, :atom},
        default: [],
        doc: "Other agent ids that must be running before this agent starts"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Arbitrary metadata stored alongside the configuration"
      ]
    ]
  end

  @doc """
  Validates and normalises a configuration map or keyword list into an
  `%Synapse.Orchestrator.AgentConfig{}` struct.

  Returns `{:ok, struct}` on success or `{:error, %NimbleOptions.ValidationError{}}` on failure.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, ValidationError.t()}
  def new(config) when is_map(config), do: config |> Map.to_list() |> new()

  def new(config) when is_list(config) do
    with {:ok, validated} <- NimbleOptions.validate(config, schema()),
         {:ok, coerced} <- enforce_archetype_rules(validated) do
      {:ok, struct(__MODULE__, Map.new(coerced))}
    end
  end

  def new(_invalid) do
    {:error,
     ValidationError.exception(
       keys_path: [],
       message: "agent configuration must be provided as a map or keyword list",
       value: nil
     )}
  end

  defp enforce_archetype_rules(validated) do
    type = Keyword.fetch!(validated, :type)
    actions = Keyword.get(validated, :actions, [])

    cond do
      type == :specialist and actions == [] ->
        {:error,
         validation_error(
           :actions,
           actions,
           "specialist agents must define at least one action module"
         )}

      type == :orchestrator and not Keyword.has_key?(validated, :orchestration) ->
        {:error,
         validation_error(
           :orchestration,
           nil,
           "orchestrator agents must include an :orchestration configuration"
         )}

      type == :custom and not Keyword.has_key?(validated, :custom_handler) ->
        {:error,
         validation_error(
           :custom_handler,
           nil,
           "custom agents must provide a :custom_handler callable"
         )}

      true ->
        {:ok, validated}
    end
  end

  @doc false
  def validate_signals(%{} = value) do
    with {:ok, subscribes} <- fetch_signal_list(value, :subscribes, required?: true),
         {:ok, emits} <- fetch_signal_list(value, :emits, required?: false) do
      {:ok, %{subscribes: subscribes, emits: emits}}
    end
  end

  def validate_signals(_),
    do:
      {:error,
       "must be a map containing :subscribes and (optional) :emits lists of router topics"}

  defp fetch_signal_list(map, key, opts) do
    value =
      Map.get(map, key) ||
        Map.get(map, Atom.to_string(key)) ||
        []

    with {:ok, list} <- ensure_topic_list(value, key, opts),
         true <- list != [] or not opts[:required?],
         {:ok, normalized} <- normalize_topics(list) do
      {:ok, normalized}
    else
      false ->
        {:error, ":#{key} must contain at least one signal topic"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_topic_list(list, _key, _opts) when is_list(list), do: {:ok, list}

  defp ensure_topic_list(value, key, opts) do
    if opts[:required?] do
      {:error, ":#{key} must be provided as a list of signal topics, got #{inspect(value)}"}
    else
      {:ok, []}
    end
  end

  defp normalize_topics(topics) do
    Enum.reduce_while(topics, {:ok, []}, fn topic, {:ok, acc} ->
      case normalize_topic(topic) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_topic(topic) when is_atom(topic) do
    if topic in Signal.topics() do
      {:ok, topic}
    else
      {:error, "unknown signal topic #{inspect(topic)}"}
    end
  end

  defp normalize_topic(topic) when is_binary(topic) do
    case Signal.topic_from_type(topic) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, "unknown signal type #{inspect(topic)}"}
    end
  end

  defp normalize_topic(topic) do
    {:error,
     "signal topics must be atoms (e.g. :review_request) or canonical type strings, got #{inspect(topic)}"}
  end

  @doc false
  def validate_orchestration(nil), do: {:ok, nil}

  def validate_orchestration(%{} = value) do
    with {:ok, classify_fn} <- fetch_callable(value, :classify_fn, [1]),
         {:ok, spawn_specialists} <- fetch_spawn_specialists(value),
         {:ok, aggregation_fn} <- fetch_callable(value, :aggregation_fn, [2]),
         {:ok, fast_path_fn} <- fetch_optional_callable(value, :fast_path_fn, [2]),
         {:ok, negotiate_fn} <- fetch_optional_callable(value, :negotiate_fn, [2]) do
      {:ok,
       %{
         classify_fn: classify_fn,
         spawn_specialists: spawn_specialists,
         aggregation_fn: aggregation_fn,
         fast_path_fn: fast_path_fn,
         negotiate_fn: negotiate_fn
       }}
    end
  end

  def validate_orchestration(_),
    do: {:error, "must be a map with classify_fn, spawn_specialists, and aggregation_fn"}

  defp fetch_spawn_specialists(map) do
    key = :spawn_specialists

    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      list when is_list(list) ->
        if Enum.all?(list, &is_atom/1) do
          {:ok, list}
        else
          {:error, "spawn_specialists list must contain only atom agent ids"}
        end

      nil ->
        {:error, "spawn_specialists must be supplied for orchestrators"}

      callable ->
        fetch_callable(%{key => callable}, key, [1])
    end
  end

  defp fetch_optional_callable(map, key, arities) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      nil -> {:ok, nil}
      _callable -> fetch_callable(map, key, arities)
    end
  end

  defp fetch_callable(map, key, arities) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))

    cond do
      is_nil(value) ->
        {:error, to_string(key) <> " must be provided"}

      callable?(value, arities) ->
        {:ok, value}

      true ->
        {:error,
         ":#{key} must be a function with arity #{Enum.join(arities, " or ")} or an MFA tuple"}
    end
  end

  defp callable?({module, function, args}, _arities)
       when is_atom(module) and is_atom(function) and is_list(args),
       do: true

  defp callable?(fun, arities) when is_function(fun) do
    Enum.any?(arities, &is_function(fun, &1))
  end

  defp callable?(_, _), do: false

  defp validation_error(key, value, message) do
    ValidationError.exception(
      keys_path: [key],
      key: key,
      value: value,
      message: message
    )
  end
end
