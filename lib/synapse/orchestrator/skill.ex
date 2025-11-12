defmodule Synapse.Orchestrator.Skill do
  @moduledoc """
  Data structure representing a discovered skill artefact.

  Skills are intentionally lightweight: metadata is always available, while the
  `body` (instructions) is loaded on demand to support progressive disclosure.
  """

  @type source :: :synapse | :claude

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          version: String.t() | nil,
          allowed_tools: [String.t()],
          dependencies: [String.t()],
          metadata: map(),
          source: source(),
          path: String.t(),
          instructions_path: String.t(),
          body: String.t() | nil,
          body_loaded?: boolean()
        }

  @enforce_keys [:id, :name, :description, :path, :instructions_path, :source]
  defstruct [
    :id,
    :name,
    :description,
    :version,
    :source,
    :path,
    :instructions_path,
    allowed_tools: [],
    dependencies: [],
    metadata: %{},
    body: nil,
    body_loaded?: false
  ]
end
