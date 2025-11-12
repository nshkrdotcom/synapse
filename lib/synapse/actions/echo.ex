defmodule Synapse.Actions.Echo do
  @moduledoc """
  Simple echo action that returns its input.
  Used to verify Jido integration is working correctly.
  """

  use Jido.Action,
    name: "echo",
    description: "Echoes back the input message",
    schema: [
      message: [type: :string, required: true, doc: "The message to echo"]
    ]

  @impl true
  def run(params, _context) do
    # Validate that message is present
    case Map.fetch(params, :message) do
      {:ok, _message} ->
        # Return all params (preserves metadata if present)
        {:ok, params}

      :error ->
        {:error, "message is required"}
    end
  end
end
