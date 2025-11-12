defmodule Synapse.TestSupport.AgentHelpers do
  @moduledoc """
  Test helpers for Jido agent testing, optimized for stateless struct-based agents.

  Provides cleaner assertion syntax and common patterns for testing agent state,
  results, and lifecycle callbacks.

  ## Usage

      import Synapse.TestSupport.AgentHelpers

      test "agent updates state" do
        agent = MyAgent.new()
        {:ok, agent, _} = MyAgent.cmd(agent, {MyAction, params})

        # Cleaner assertions
        assert_agent_state(agent, field: value)
        assert_agent_result(agent, expected_result)

        # Extract state for complex assertions
        state = get_agent_state(agent)
        assert length(state.history) > 0
      end

  ## Examples

      # Assert single field
      assert_agent_state(agent, review_count: 1)

      # Assert multiple fields
      assert_agent_state(agent, review_count: 1, learned_patterns: [])

      # Assert with map
      assert_agent_state(agent, %{review_count: 1, learned_patterns: []})

      # Extract state for custom assertions
      state = get_agent_state(agent)
      assert [%{confidence: conf}] = state.decision_fossils
      assert conf > 0.5
  """

  import ExUnit.Assertions

  @doc """
  Asserts that agent state matches expected values.

  Accepts either a keyword list or map of expected state values.
  Only checks specified fields - other fields are ignored.

  ## Examples

      # Single field
      assert_agent_state(agent, review_count: 1)

      # Multiple fields
      assert_agent_state(agent, review_count: 1, learned_patterns: [])

      # Map syntax
      assert_agent_state(agent, %{review_count: 1, learned_patterns: []})
  """
  @spec assert_agent_state(struct(), keyword() | map()) :: :ok
  def assert_agent_state(%_{state: state} = _agent, expected) when is_list(expected) do
    Enum.each(expected, fn {key, expected_value} ->
      actual_value = Map.get(state, key)

      assert actual_value == expected_value,
             """
             Agent state mismatch for key :#{key}

             Expected: #{inspect(expected_value)}
             Actual:   #{inspect(actual_value)}

             Full state: #{inspect(state, pretty: true, limit: :infinity)}
             """
    end)

    :ok
  end

  def assert_agent_state(%_{state: state} = _agent, expected) when is_map(expected) do
    Enum.each(expected, fn {key, expected_value} ->
      actual_value = Map.get(state, key)

      assert actual_value == expected_value,
             """
             Agent state mismatch for key :#{key}

             Expected: #{inspect(expected_value)}
             Actual:   #{inspect(actual_value)}

             Full state: #{inspect(state, pretty: true, limit: :infinity)}
             """
    end)

    :ok
  end

  @doc """
  Asserts that agent result matches expected value.

  Useful for checking action execution results without extracting the result first.

  ## Examples

      {:ok, agent, _} = Agent.cmd(agent, {Action, params})
      assert_agent_result(agent, %{message: "expected"})
  """
  @spec assert_agent_result(struct(), any()) :: :ok
  def assert_agent_result(%_{result: result} = _agent, expected) do
    assert result == expected,
           """
           Agent result mismatch

           Expected: #{inspect(expected)}
           Actual:   #{inspect(result)}
           """

    :ok
  end

  @doc """
  Extracts state from agent struct.

  Useful for complex assertions that don't fit the assert_agent_state pattern.

  ## Examples

      state = get_agent_state(agent)
      assert length(state.review_history) == 100
      assert Enum.all?(state.review_history, &Map.has_key?(&1, :confidence))
  """
  @spec get_agent_state(struct()) :: map()
  def get_agent_state(%_{state: state}), do: state

  @doc """
  Extracts result from agent struct.

  Useful for complex result assertions.

  ## Examples

      result = get_agent_result(agent)
      assert result.confidence > 0.7
      assert length(result.issues) == 0
  """
  @spec get_agent_result(struct()) :: any()
  def get_agent_result(%_{result: result}), do: result

  @doc """
  Asserts that a specific key exists in agent state with any value.

  ## Examples

      assert_agent_state_has_key(agent, :review_count)
  """
  @spec assert_agent_state_has_key(struct(), atom()) :: :ok
  def assert_agent_state_has_key(%_{state: state} = _agent, key) do
    assert Map.has_key?(state, key),
           """
           Agent state does not contain key :#{key}

           Available keys: #{inspect(Map.keys(state))}
           """

    :ok
  end

  @doc """
  Asserts that agent state field matches a pattern.

  Useful for partial matching or pattern-based assertions.

  ## Examples

      # Assert list has one item with specific structure
      assert_agent_state_matches(agent, :decision_fossils, [%{confidence: _}])

      # Assert value is within range
      assert_agent_state_matches(agent, :review_count, count) when count > 0
  """
  defmacro assert_agent_state_matches(agent, key, pattern) do
    quote do
      state = get_agent_state(unquote(agent))
      value = Map.get(state, unquote(key))

      assert match?(unquote(pattern), value),
             """
             Agent state field :#{unquote(key)} does not match pattern

             Pattern:  #{unquote(Macro.to_string(pattern))}
             Actual:   #{inspect(value)}
             """
    end
  end

  @doc """
  Executes an agent command and returns the updated agent.

  Helper to reduce boilerplate in tests.

  ## Examples

      agent = MyAgent.new()
      agent = exec_agent_cmd(agent, {MyAction, %{param: "value"}})
      assert_agent_state(agent, executed: true)
  """
  @spec exec_agent_cmd(struct(), tuple()) :: struct()
  def exec_agent_cmd(agent, action_tuple) do
    module = agent.__struct__

    case module.cmd(agent, action_tuple) do
      {:ok, updated_agent, _directives} -> updated_agent
      {:error, error} -> raise "Agent command failed: #{inspect(error)}"
    end
  end

  @doc """
  Executes multiple agent commands in sequence and returns the final agent.

  ## Examples

      agent = MyAgent.new()
      agent = exec_agent_cmds(agent, [
        {Action1, %{param: "value1"}},
        {Action2, %{param: "value2"}},
        {Action3, %{param: "value3"}}
      ])
  """
  @spec exec_agent_cmds(struct(), [tuple()]) :: struct()
  def exec_agent_cmds(agent, action_tuples) when is_list(action_tuples) do
    Enum.reduce(action_tuples, agent, fn action_tuple, acc_agent ->
      exec_agent_cmd(acc_agent, action_tuple)
    end)
  end
end
