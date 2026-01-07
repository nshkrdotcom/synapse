defmodule Synapse.Signal.Registry do
  @moduledoc """
  Runtime registry for signal topics and their schemas.

  Topics can be declared via application configuration or registered at runtime.
  An ETS backend provides fast concurrent reads while validations run inside the
  GenServer process.
  """

  use GenServer

  require Logger

  alias Synapse.Signal.Schema

  @typedoc "Canonical signal topic"
  @type topic :: atom()

  @typedoc "Normalized topic configuration stored in ETS"
  @type topic_config :: %{
          type: String.t(),
          schema: NimbleOptions.t() | nil,
          raw_schema: keyword() | module() | nil,
          validator: (map() -> map())
        }

  @doc """
  Starts the registry.

  Options:
    * `:name` - Registry name (defaults to `#{inspect(__MODULE__)}`)
    * `:topics` - Topics to preload instead of application config
    * `:domains` - Domains to auto-register during startup (defaults to config :synapse, :domains)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {name, opts}, name: name)
  end

  @doc """
  Registers a new topic backed by the provided config.
  """
  @spec register_topic(atom() | pid(), topic(), map() | keyword()) ::
          :ok | {:error, term()}
  def register_topic(registry \\ __MODULE__, topic, config)

  def register_topic(registry, topic, config) when is_atom(topic) do
    with {:ok, tables} <- fetch_tables(registry),
         {:ok, normalized} <- normalize_topic_config(config) do
      do_register_topic(tables, topic, normalized)
    end
  end

  def register_topic(_registry, topic, _config),
    do: {:error, {:invalid_topic, topic}}

  @doc """
  Unregisters a topic.
  """
  @spec unregister_topic(atom() | pid(), topic()) :: :ok | {:error, term()}
  def unregister_topic(registry \\ __MODULE__, topic) when is_atom(topic) do
    with {:ok, tables} <- fetch_tables(registry) do
      do_unregister_topic(tables, topic)
    end
  end

  @doc """
  Retrieves the stored configuration for a topic.
  """
  @spec get_topic(atom() | pid(), topic()) :: {:ok, topic_config()} | {:error, term()}
  def get_topic(registry \\ __MODULE__, topic) when is_atom(topic) do
    with {:ok, tables} <- fetch_tables(registry) do
      case :ets.lookup(tables.topics_table, topic) do
        [{^topic, config}] -> {:ok, config}
        [] -> {:error, :not_found}
      end
    end
  end

  @doc """
  Lists all registered topics.
  """
  @spec list_topics(atom() | pid()) :: [topic()]
  def list_topics(registry \\ __MODULE__) do
    case fetch_tables(registry) do
      {:ok, tables} ->
        tables.topics_table
        |> :ets.tab2list()
        |> Enum.map(fn {topic, _config} -> topic end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Resolves a topic atom to its wire-format type.
  """
  @spec type(atom() | pid(), topic()) :: String.t()
  def type(registry \\ __MODULE__, topic) do
    registry
    |> fetch_topic!(topic)
    |> Map.fetch!(:type)
  end

  @doc """
  Resolves a wire-format type to the registered topic.
  """
  @spec topic_from_type(atom() | pid(), String.t()) :: {:ok, topic()} | :error
  def topic_from_type(registry \\ __MODULE__, type) when is_binary(type) do
    case fetch_tables(registry) do
      {:ok, tables} ->
        case :ets.lookup(tables.types_table, type) do
          [{^type, topic}] -> {:ok, topic}
          [] -> :error
        end

      {:error, _} ->
        :error
    end
  end

  @doc """
  Validates a payload against the topic schema and returns the normalized map.

  Raises `KeyError` for unknown topics and `ArgumentError` on validation errors.
  """
  @spec validate!(atom() | pid(), topic(), map()) :: map()
  def validate!(registry \\ __MODULE__, topic, payload) when is_map(payload) do
    validator =
      registry
      |> fetch_topic!(topic)
      |> Map.fetch!(:validator)

    validator.(payload)
  end

  ## GenServer callbacks

  @impl true
  def init({name, opts}) do
    Process.flag(:trap_exit, true)

    topics_table = opts[:topics_table] || :"#{name}_signal_topics"
    types_table = opts[:types_table] || :"#{name}_signal_types"

    :ets.new(topics_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(types_table, [:set, :named_table, :public, read_concurrency: true])

    state = %{
      name: name,
      topics_table: topics_table,
      types_table: types_table
    }

    :persistent_term.put(pt_key(name), state)
    :persistent_term.put(pt_key(self()), state)

    state =
      state
      |> load_config_topics(opts)
      |> register_configured_domains(opts)

    {:ok, state}
  end

  @impl true
  def terminate(_reason, %{name: name}) do
    :persistent_term.erase(pt_key(name))
    :persistent_term.erase(pt_key(self()))
    :ok
  end

  ## Helpers

  defp fetch_tables(registry) do
    ensure_started(registry)

    case :persistent_term.get(pt_key(registry), :not_found) do
      :not_found -> {:error, :not_started}
      tables -> {:ok, tables}
    end
  end

  defp ensure_started(registry) do
    if registry == __MODULE__ and is_nil(Process.whereis(registry)) do
      case GenServer.start(__MODULE__, {registry, []}, name: registry) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, _reason} -> :ok
      end
    else
      :ok
    end
  end

  defp fetch_topic!(registry, topic) do
    case get_topic(registry, topic) do
      {:ok, config} -> config
      {:error, :not_started} -> raise KeyError, key: topic, term: registry
      {:error, :not_found} -> raise KeyError, key: topic, term: registry
    end
  end

  defp do_register_topic(tables, topic, %{type: type} = config) do
    case :ets.lookup(tables.topics_table, topic) do
      [] ->
        case :ets.lookup(tables.types_table, type) do
          [] ->
            :ets.insert(tables.topics_table, {topic, config})
            :ets.insert(tables.types_table, {type, topic})
            :ok

          [{^type, ^topic}] ->
            :ok

          [{^type, existing}] ->
            {:error, {:type_conflict, existing}}
        end

      _ ->
        {:error, :already_registered}
    end
  end

  defp do_unregister_topic(tables, topic) do
    type =
      case :ets.lookup(tables.topics_table, topic) do
        [{^topic, %{type: type}}] -> type
        _ -> nil
      end

    :ets.delete(tables.topics_table, topic)
    if type, do: :ets.delete(tables.types_table, type)
    :ok
  end

  defp load_config_topics(state, opts) do
    topics =
      case Keyword.fetch(opts, :topics) do
        {:ok, value} -> value
        :error -> Application.get_env(:synapse, __MODULE__, []) |> Keyword.get(:topics, [])
      end

    register_topics(state, topics, on_error: :raise)
    state
  end

  defp register_configured_domains(state, opts) do
    domains =
      case Keyword.fetch(opts, :domains) do
        {:ok, value} -> value
        :error -> Application.get_env(:synapse, :domains, [])
      end

    Enum.each(domains, &register_domain(&1, state.name))

    state
  end

  defp register_domain(domain, registry_name) do
    case Code.ensure_loaded(domain) do
      {:module, _} ->
        case call_domain_register(domain, registry_name) do
          :ok ->
            :ok

          {:error, :already_registered} ->
            :ok

          {:error, :missing_register} ->
            Logger.warning(
              "Domain #{inspect(domain)} is configured but does not implement register/0 or register/1"
            )

          {:error, reason} ->
            Logger.warning("Failed to register domain #{inspect(domain)}: #{inspect(reason)}")

          other ->
            Logger.warning(
              "Domain #{inspect(domain)} returned unexpected value from register: #{inspect(other)}"
            )
        end

      {:error, reason} ->
        Logger.warning("Failed to load domain #{inspect(domain)}: #{inspect(reason)}")
    end
  end

  defp call_domain_register(domain, registry_name) do
    cond do
      function_exported?(domain, :register, 1) ->
        domain.register(registry_name)

      function_exported?(domain, :register, 0) ->
        domain.register()

      true ->
        {:error, :missing_register}
    end
  end

  defp register_topics(state, topics, opts) when is_list(topics) do
    Enum.each(topics, fn {topic, config} ->
      result =
        case normalize_topic_config(config) do
          {:ok, normalized} -> do_register_topic(state, topic, normalized)
          {:error, reason} -> {:error, reason}
        end

      case result do
        :ok ->
          :ok

        {:error, reason} ->
          handle_topic_error(topic, reason, opts)
      end
    end)
  end

  defp handle_topic_error(topic, reason, opts) do
    case opts[:on_error] do
      :ignore -> :ok
      _ -> raise ArgumentError, "invalid config for #{inspect(topic)}: #{inspect(reason)}"
    end
  end

  defp normalize_topic_config(config) when is_map(config),
    do: config |> Map.to_list() |> normalize_topic_config()

  defp normalize_topic_config(config) when is_list(config) do
    with {:ok, type} <- fetch_type(config),
         {:ok, schema} <- fetch_schema(config) do
      {:ok,
       %{
         type: type,
         schema: schema.compiled,
         raw_schema: schema.raw,
         validator: schema.validator
       }}
    end
  end

  defp normalize_topic_config(_config), do: {:error, :invalid_config}

  defp fetch_type(config) do
    case Keyword.fetch(config, :type) do
      {:ok, type} when is_binary(type) -> {:ok, type}
      {:ok, other} -> {:error, {:invalid_type, other}}
      :error -> {:error, :type_required}
    end
  end

  defp fetch_schema(config) do
    case Keyword.fetch(config, :schema) do
      {:ok, schema} -> normalize_schema(schema)
      :error -> {:error, :schema_required}
    end
  end

  defp normalize_schema(schema) when is_list(schema) do
    compiled = NimbleOptions.new!(schema)

    {:ok,
     %{
       compiled: compiled,
       raw: schema,
       validator: Schema.compile_schema(schema)
     }}
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, e}
  end

  defp normalize_schema(schema) when is_atom(schema) do
    with {:module, _} <- Code.ensure_loaded(schema),
         true <- function_exported?(schema, :validate!, 1) do
      validator = fn payload -> schema.validate!(payload) end

      compiled =
        if function_exported?(schema, :schema, 0) do
          schema.schema()
        else
          nil
        end

      {:ok, %{compiled: compiled, raw: schema, validator: validator}}
    else
      _ -> {:error, {:invalid_schema_module, schema}}
    end
  end

  defp normalize_schema(%NimbleOptions{} = schema) do
    {:ok,
     %{
       compiled: schema,
       raw: nil,
       validator: fn payload ->
         payload
         |> Schema.normalize_payload()
         |> NimbleOptions.validate!(schema)
         |> Map.new()
       end
     }}
  end

  defp normalize_schema(_schema), do: {:error, :invalid_schema}

  defp pt_key(name), do: {__MODULE__, name}
end
