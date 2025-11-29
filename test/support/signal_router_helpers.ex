defmodule Synapse.TestSupport.SignalRouterHelpers do
  @moduledoc """
  Test helpers for working with `Synapse.SignalRouter`.

  Provides utilities for spinning up isolated routers, publishing signals,
  subscribing the test process, and asserting on recorded signals.
  """

  import ExUnit.Assertions
  alias Synapse.SignalRouter

  @doc """
  Starts a dedicated SignalRouter for tests.

  Options:
    * `:name` - Router name (defaults to a unique atom)
    * `:bus_name` - Underlying bus name
    * `:router_opts` - Additional options passed to `SignalRouter.start_link/1`
  """
  def start_test_router(opts \\ []) do
    name = Keyword.get(opts, :name, :"router_#{System.unique_integer([:positive])}")
    bus_name = Keyword.get(opts, :bus_name, :"#{name}_bus")

    router_opts =
      opts
      |> Keyword.get(:router_opts, [])
      |> Keyword.merge(name: name, bus_name: bus_name)

    {:ok, pid} = SignalRouter.start_link(router_opts)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    name
  end

  @doc """
  Sets up a router and optional subscriptions for the current test.
  """
  def setup_test_router(_context, opts \\ []) do
    router = start_test_router(opts)
    topics = Keyword.get(opts, :subscribe, [])

    subscriptions =
      Enum.map(topics, fn topic ->
        sub_id = subscribe_test_process(router, topic)
        {topic, sub_id}
      end)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(subscriptions, fn {_topic, sub_id} ->
        safe_unsubscribe(router, sub_id)
      end)
    end)

    {:ok, %{router: router, signal_router_subscriptions: subscriptions}}
  end

  @doc """
  Publishes a signal for the given topic using the router.
  """
  def publish_signal(router, topic, data, opts \\ []) do
    {:ok, signal} = SignalRouter.publish(router, topic, data, opts)
    signal.id
  end

  @doc """
  Subscribes the calling process to a topic.
  """
  def subscribe_test_process(router, topic) do
    {:ok, sub_id} = SignalRouter.subscribe(router, topic)
    sub_id
  end

  @doc """
  Waits for a signal matching the given topic or type string.
  """
  def await_signal(topic_or_type, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1_000)
    deadline = System.monotonic_time(:millisecond) + timeout
    type = normalize_type(topic_or_type)

    do_await_signal(type, deadline, timeout)
  end

  defp do_await_signal(type, deadline, original_timeout) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining == 0 do
      flunk("Did not receive signal matching #{type} within #{original_timeout}ms")
    else
      receive do
        {:signal, signal} ->
          if signal.type == type do
            signal
          else
            do_await_signal(type, deadline, original_timeout)
          end

        other ->
          flunk("Received unexpected message #{inspect(other)} while waiting for #{type}")
      after
        remaining ->
          flunk("Did not receive signal matching #{type} within #{original_timeout}ms")
      end
    end
  end

  @doc """
  Replays historical signals for the topic.
  """
  def replay_signals(router, topic, opts \\ []) do
    case SignalRouter.replay(router, topic, opts) do
      {:ok, signals} -> signals
      {:error, reason} -> flunk("Failed to replay signals: #{inspect(reason)}")
    end
  end

  @doc """
  Asserts that at least one signal exists for the topic.
  """
  def assert_signal_exists(router, topic) do
    signals = replay_signals(router, topic)

    case List.first(signals) do
      nil -> flunk("Expected to find a signal for #{inspect(topic)}, but history is empty")
      signal -> signal
    end
  end

  @doc """
  Asserts the number of recorded signals for the topic.
  """
  def assert_signal_count(router, topic, expected_count) do
    signals = replay_signals(router, topic)

    assert length(signals) == expected_count,
           "Expected #{expected_count} signals for #{inspect(topic)}, found #{length(signals)}"
  end

  defp normalize_type(topic) when is_atom(topic), do: Synapse.Signal.type(topic)
  defp normalize_type(type) when is_binary(type), do: type

  defp safe_unsubscribe(router, sub_id) do
    if Process.whereis(router) do
      try do
        SignalRouter.unsubscribe(router, sub_id)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
