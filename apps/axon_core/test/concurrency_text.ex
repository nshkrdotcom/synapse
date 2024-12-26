# axon/test/axon/concurrency_test.exs

defmodule Axon.ConcurrencyTest do
  use ExUnit.Case, async: true
  # Use a different alias if you're not using HTTPClient directly in your tests
  # alias Axon.Agent.HTTPClient, as: TestHTTPClient
  import Axon.Agent, only: [send_message: 2]
  # doctest Axon

  setup do
    # Start your application or necessary supervisors
    # You might need to adjust this depending on your application's setup
    # :ok = Application.ensure_all_started(:axon)
    start_supervised(Axon.Application)

    # If you have any setup to do before tests, like starting agents, do it here
    # For example, if you need to register agents or set up some initial state:
    # ensure_agents_started()

    :ok
  end

  @tag timeout: :infinity
  test "handle concurrent requests to multiple agents" do
    agent_ids = ["python_agent_1", "python_agent_2"]

    tasks =
      for agent_id <- agent_ids, _ <- 1..10 do
        Task.async(fn ->
          # use unique prompt for each request to avoid caching issues
          prompt = "What is the weather in #{agent_id} on #{:rand.uniform(1000)}?"

          case send_message(agent_id, %{prompt: prompt}) do
            {:ok, result} ->
              assert is_binary(result)
            {:error, reason} ->
              flunk("Agent #{agent_id} failed: #{reason}")
          end
        end)
      end

    # Await all tasks and pattern match to unwrap results
    for task <- tasks do
      assert {:ok, _result} = Task.await(task, 60_000)
    end
  end

  @tag timeout: :infinity
  test "handle concurrent requests to the same agent" do
    agent_id = "python_agent_1"

    tasks =
      for _ <- 1..10 do
        Task.async(fn ->
          prompt = "What is the weather in #{agent_id} on #{:rand.uniform(1000)}?"
          case send_message(agent_id, %{prompt: prompt}) do
            {:ok, result} ->
              assert is_binary(result)

            {:error, reason} ->
              flunk("Agent #{agent_id} failed: #{reason}")
          end
        end)
      end

    for task <- tasks do
      assert {:ok, _result} = Task.await(task, 60_000)
    end
  end
end
