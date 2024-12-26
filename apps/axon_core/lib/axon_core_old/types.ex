defmodule AxonCore.Types do
  @type agent_id :: String.t()
  @type message :: map() # Define a more specific type for messages later
  @type error_reason :: String.t() | :timeout | :unknown_agent | :validation_error

  # Potentially define a struct for representing agent configuration
  defstruct [:name, :python_module, :model, :config]
end
