defmodule Synapse.SignalRouter do
  @moduledoc """
  Runtime wrapper around `Jido.Signal.Bus` that enforces signal contracts,
  centralizes publish/subscribe ergonomics, and enables targeted delivery
  to specialists without leaking process identifiers.
  """

  use GenServer
  require Logger

  alias Synapse.{AgentRegistry, Signal}

  defstruct [
    :name,
    :bus,
    :registry,
    bus_subscriptions: %{},
    subscribers: %{},
    topic_index: %{},
    monitor_index: %{}
  ]

  @typedoc "Unique subscription identifier returned by `subscribe/3`."
  @type subscription_id :: reference()

  defmodule InvalidTopicError do
    defexception [:topic, plug: "Invalid signal topic"]

    @impl true
    def message(%__MODULE__{topic: topic}) do
      "unknown signal topic #{inspect(topic)}"
    end
  end

  defmodule RegistryNotConfiguredError do
    defexception [:message]
  end

  ## Client API

  @doc """
  Starts the router process and its dedicated signal bus.

  Options:
    * `:name` - router identifier (defaults to #{inspect(__MODULE__)})
    * `:bus_name` - name of the underlying `Jido.Signal.Bus`
    * `:registry` - `Synapse.AgentRegistry` name for targeted delivery helpers
    * `:bus_opts` - additional options passed to `Jido.Signal.Bus.start_link/1`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {name, opts}, name: name)
  end

  @doc """
  Publishes a signal for the given topic after validating the payload.

  Accepted options:
    * `:source` - logical source URI (defaults to \"/synapse/router\")
    * `:subject` - optional subject string
    * `:meta` - metadata map merged into the signal struct
  """
  @spec publish(atom(), Signal.topic(), map(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def publish(router \\ __MODULE__, topic, payload, opts \\ []) do
    %{bus: bus, name: router_name} = fetch(router)

    signal =
      topic
      |> build_signal(payload, opts)
      |> tap(fn _ ->
        :telemetry.execute(
          [:synapse, :signal_router, :publish],
          %{count: 1},
          %{topic: topic, router: router_name}
        )
      end)

    case Jido.Signal.Bus.publish(bus, [signal]) do
      {:ok, _records} -> {:ok, signal}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Subscribes the caller (or provided `:target`) to a validated topic stream.
  """
  @spec subscribe(atom(), Signal.topic(), keyword()) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(router \\ __MODULE__, topic, opts \\ []) do
    validate_topic!(topic)
    GenServer.call(router, {:subscribe, topic, opts})
  end

  @doc """
  Cancels a subscription created via `subscribe/3`.
  """
  @spec unsubscribe(atom(), subscription_id()) :: :ok
  def unsubscribe(router \\ __MODULE__, subscription_id) do
    GenServer.call(router, {:unsubscribe, subscription_id})
  end

  @doc """
  Replays historical signals for the given topic.
  """
  @spec replay(atom(), Signal.topic(), keyword()) :: {:ok, [Jido.Signal.t()]} | {:error, term()}
  def replay(router \\ __MODULE__, topic, opts \\ []) do
    %{bus: bus} = fetch(router)
    type = Signal.type(topic)
    since = Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -3600, :second))
    limit = Keyword.get(opts, :limit, 100)

    Jido.Signal.Bus.replay(bus, type, since, limit: limit)
  end

  @doc """
  Dispatches a review request to a specialist identified by registry id.
  """
  @spec cast_to_specialist(atom(), AgentRegistry.agent_id(), Jido.Signal.t(), keyword()) ::
          :ok | {:error, term()}
  def cast_to_specialist(router \\ __MODULE__, specialist_id, signal, opts \\ []) do
    %{registry: default_registry} = fetch(router)
    registry = Keyword.get(opts, :registry, default_registry)

    if is_nil(registry) do
      raise RegistryNotConfiguredError,
            "SignalRouter #{inspect(router)} does not have a registry configured"
    end

    case AgentRegistry.lookup(registry, specialist_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:process_review_request, signal})
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Acknowledges a signal delivery (placeholder hook for future durability).
  """
  @spec ack(atom(), Jido.Signal.t()) :: :ok
  def ack(_router \\ __MODULE__, _signal), do: :ok

  @doc """
  Retries a publish with the provided payload and options.
  """
  @spec retry(atom(), Signal.topic(), map(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def retry(router \\ __MODULE__, topic, payload, opts \\ []) do
    publish(router, topic, payload, opts)
  end

  @doc """
  Fetches router metadata (bus, registry, name) from persistent storage.
  """
  @spec fetch(atom()) :: %{bus: atom(), registry: atom() | nil, name: atom()}
  def fetch(name \\ __MODULE__) do
    case :persistent_term.get(router_key(name), :not_found) do
      :not_found -> raise "SignalRouter #{inspect(name)} has not been started"
      info -> info
    end
  end

  ## GenServer callbacks

  @impl true
  def init({name, opts}) do
    Process.flag(:trap_exit, true)

    bus_name = Keyword.get(opts, :bus_name, :"#{name}_bus")
    registry = Keyword.get(opts, :registry)
    bus_opts = Keyword.get(opts, :bus_opts, [])

    {:ok, _pid} =
      Jido.Signal.Bus.start_link(Keyword.merge([name: bus_name], bus_opts))

    state = %__MODULE__{
      name: name,
      bus: bus_name,
      registry: registry,
      bus_subscriptions: %{},
      subscribers: %{},
      topic_index: Map.new(Signal.topics(), &{&1, MapSet.new()}),
      monitor_index: %{}
    }

    :persistent_term.put(router_key(name), %{name: name, bus: bus_name, registry: registry})

    {:ok, subscribe_to_topics(state)}
  end

  @impl true
  def handle_call({:subscribe, topic, opts}, {from_pid, _} = _from, state) do
    state = ensure_topic!(state, topic)
    target = Keyword.get(opts, :target, from_pid)
    sub_id = make_ref()
    monitor_ref = Process.monitor(target)

    subscribers =
      Map.put(state.subscribers, sub_id, %{
        topic: topic,
        target: target,
        monitor_ref: monitor_ref
      })

    topic_index =
      Map.update!(state.topic_index, topic, fn ids ->
        MapSet.put(ids, sub_id)
      end)

    monitor_index = Map.put(state.monitor_index, monitor_ref, sub_id)

    {:reply, {:ok, sub_id},
     %{state | subscribers: subscribers, topic_index: topic_index, monitor_index: monitor_index}}
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    {entry, subscribers} = Map.pop(state.subscribers, subscription_id)

    if entry do
      Process.demonitor(entry.monitor_ref, [:flush])

      topic_index =
        Map.update!(state.topic_index, entry.topic, fn ids ->
          MapSet.delete(ids, subscription_id)
        end)

      monitor_index = Map.delete(state.monitor_index, entry.monitor_ref)

      {:reply, :ok,
       %{state | subscribers: subscribers, topic_index: topic_index, monitor_index: monitor_index}}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{} = signal}, state) do
    with {:ok, topic} <- Signal.topic_from_type(signal.type) do
      payload = Map.get(signal, :data) || %{}
      validated = Signal.validate!(topic, payload)
      updated_signal = %{signal | data: validated}

      dispatch(topic, updated_signal, state)
    else
      :error ->
        Logger.warning("SignalRouter received unknown signal type", type: signal.type)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitor_index, ref) do
      {nil, _} ->
        {:noreply, state}

      {subscription_id, monitor_index} ->
        {entry, subscribers} = Map.pop(state.subscribers, subscription_id)

        topic_index =
          if entry do
            Map.update!(state.topic_index, entry.topic, fn ids ->
              MapSet.delete(ids, subscription_id)
            end)
          else
            state.topic_index
          end

        {:noreply,
         %{
           state
           | subscribers: subscribers,
             topic_index: topic_index,
             monitor_index: monitor_index
         }}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.bus_subscriptions, fn {_topic, sub_id} ->
      Jido.Signal.Bus.unsubscribe(state.bus, sub_id)
    end)

    :ok
  end

  ## Internal helpers

  defp build_signal(topic, payload, opts) do
    validated_payload = Signal.validate!(topic, payload)

    attrs =
      %{
        type: Signal.type(topic),
        source: Keyword.get(opts, :source, "/synapse/router"),
        data: validated_payload
      }
      |> maybe_put(:subject, Keyword.get(opts, :subject))
      |> maybe_merge_metadata(Keyword.get(opts, :meta, %{}))

    {:ok, signal} = Jido.Signal.new(attrs)
    signal
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_merge_metadata(map, meta) when meta in [nil, %{}], do: map
  defp maybe_merge_metadata(map, meta), do: Map.merge(map, meta)

  defp validate_topic!(topic) do
    if topic in Signal.topics() do
      :ok
    else
      raise InvalidTopicError, topic: topic
    end
  end

  defp ensure_topic!(state, topic) do
    cond do
      Map.has_key?(state.topic_index, topic) ->
        state

      topic in Signal.topics() ->
        subscribe_topic(state, topic)

      true ->
        raise InvalidTopicError, topic: topic
    end
  end

  defp subscribe_to_topics(state) do
    bus_subscriptions =
      Enum.reduce(Signal.topics(), %{}, fn topic, acc ->
        type = Signal.type(topic)

        case Map.fetch(acc, topic) do
          {:ok, _} ->
            acc

          :error ->
            {:ok, sub_id} =
              Jido.Signal.Bus.subscribe(
                state.bus,
                type,
                dispatch: {:pid, target: self(), delivery_mode: :async}
              )

            Map.put(acc, topic, sub_id)
        end
      end)

    %{state | bus_subscriptions: bus_subscriptions}
  end

  defp subscribe_topic(state, topic) do
    type = Signal.type(topic)

    {:ok, sub_id} =
      Jido.Signal.Bus.subscribe(
        state.bus,
        type,
        dispatch: {:pid, target: self(), delivery_mode: :async}
      )

    %{
      state
      | topic_index: Map.put(state.topic_index, topic, MapSet.new()),
        bus_subscriptions: Map.put(state.bus_subscriptions, topic, sub_id)
    }
  end

  defp dispatch(topic, signal, state) do
    subscriber_ids = Map.get(state.topic_index, topic, MapSet.new())
    delivery_count = Enum.count(subscriber_ids)

    Enum.each(subscriber_ids, fn subscription_id ->
      if subscriber = state.subscribers[subscription_id] do
        send(subscriber.target, {:signal, signal})
      end
    end)

    :telemetry.execute(
      [:synapse, :signal_router, :deliver],
      %{count: delivery_count},
      %{topic: topic, router: state.name}
    )
  end

  defp router_key(name), do: {__MODULE__, name}
end
