defmodule Axon.RunRequest do
  @moduledoc """
  Defines the structure for a request to run an agent.
  """
  defstruct [
    :agent_id,
    :prompt,
    :message_history,
    :model_settings
  ]
end

defmodule Axon.RunResponse do
  @moduledoc """
  Defines the structure for a response from running an agent.
  """
  defstruct [
    :result,
    :usage
  ]
end

defmodule Axon.Usage do
  @moduledoc """
  Defines the structure for usage information.
  """
  defstruct [
    :request_tokens,
    :response_tokens,
    :total_tokens
  ]
end
