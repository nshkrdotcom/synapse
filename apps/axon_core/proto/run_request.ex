defmodule Axon.RunRequest do
  @moduledoc """
  Struct representing a run request to the agent.
  """
  defstruct [
    :agent_id,
    :prompt,
    :message_history,  # Added to match Python side
    :model_settings    # Added to match Python side
  ]
end

defmodule Axon.Usage do
  @moduledoc """
  Struct representing token usage information from the agent.
  """
  defstruct [:request_tokens, :response_tokens, :total_tokens]
end

defmodule Axon.RunResponse do
  @moduledoc """
  Struct representing a response from the agent.
  """
  defstruct [:result, :usage]
end
