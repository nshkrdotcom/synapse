defmodule Synapse.TestSupport.FakeReqLLM do
  @moduledoc """
  Lightweight stand-in for Synapse.ReqLLM used in tests.

  Responses are configured per test and consumed sequentially.
  """

  alias Jido.Error

  @state_key {:synapse, :fake_req_llm_state}

  @doc """
  Sets the queue of responses the fake LLM will return.

  Each entry should be either `{:ok, map}` or `{:error, %Jido.Error{}}`.
  """
  def set_responses(responses) when is_list(responses) do
    normalized =
      Enum.map(responses, fn
        {:ok, response} -> {:ok, response}
        {:error, %Error{} = error} -> {:error, error}
        {:error, message} when is_binary(message) -> {:error, Error.execution_error(message)}
      end)

    :persistent_term.put(@state_key, %{queue: normalized, call_count: 0})
  end

  @doc """
  Returns how many times the fake LLM has been invoked.
  """
  def call_count do
    case :persistent_term.get(@state_key, %{call_count: 0}) do
      %{call_count: count} -> count
      _ -> 0
    end
  end

  @doc """
  Resets the call counter and response queue.
  """
  def reset do
    :persistent_term.erase(@state_key)
  end

  @spec chat_completion(map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def chat_completion(_params, _opts) do
    state = :persistent_term.get(@state_key, %{queue: [], call_count: 0})

    case state.queue do
      [response | rest] ->
        :persistent_term.put(@state_key, %{state | queue: rest, call_count: state.call_count + 1})
        response

      [] ->
        {:error, Error.execution_error("No fake LLM response configured")}
    end
  end
end
