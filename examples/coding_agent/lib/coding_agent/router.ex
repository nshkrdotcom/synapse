defmodule CodingAgent.Router do
  @moduledoc """
  Hard-wired routing logic for task-to-provider mapping.

  ## Routing Strategy

  Each task type is routed to the provider best suited for it:

    * `:generate` -> Claude (careful reasoning, good for complex generation)
    * `:review` -> Codex (tool-calling, good for quick review with file context)
    * `:analyze` -> Gemini (large context window, good for understanding)
    * `:explain` -> Gemini (clear explanations)
    * `:refactor` -> Claude (careful reasoning, preserves behavior)
    * `:fix` -> Codex (tool-calling, can edit files directly)

  This routing is intentionally hard-wired for the example. In production,
  you might want more sophisticated routing based on task complexity,
  code size, available providers, etc.
  """

  alias CodingAgent.Task

  @type provider :: :claude | :codex | :gemini

  @routing_table %{
    generate: :claude,
    review: :codex,
    analyze: :gemini,
    explain: :gemini,
    refactor: :claude,
    fix: :codex
  }

  @doc """
  Route a task to the appropriate provider.

  Returns the provider atom best suited for the task type.
  """
  @spec route(Task.t()) :: provider()
  def route(%Task{type: type}) do
    Map.get(@routing_table, type, :claude)
  end

  @doc """
  Get the routing table.
  """
  @spec routing_table() :: map()
  def routing_table, do: @routing_table

  @doc """
  Get all available provider atoms.
  """
  @spec available_providers() :: [provider()]
  def available_providers, do: [:claude, :codex, :gemini]

  @doc """
  Get providers suitable for a given task type.

  Returns a ranked list of providers, with the primary choice first.
  """
  @spec providers_for(Task.task_type()) :: [provider()]
  def providers_for(type) do
    primary = Map.get(@routing_table, type, :claude)
    [primary | available_providers() -- [primary]]
  end
end
