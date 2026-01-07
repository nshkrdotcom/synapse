defmodule CodingAgent.Actions.ExecuteProvider do
  @moduledoc """
  Jido Action to execute a coding task with a specific provider.
  """

  use Jido.Action,
    name: "execute_provider",
    description: "Execute a coding task with a specific AI provider",
    schema: [
      task: [type: :map, required: true, doc: "Task map with input, type, context, etc."],
      provider: [type: :atom, required: true, doc: "Provider atom: :claude, :codex, or :gemini"]
    ]

  alias CodingAgent.{Task, Providers}

  @impl true
  def run(params, _context) do
    task = build_task(params.task)
    provider = params.provider
    module = resolve_provider(provider)

    if module.available?() do
      module.execute(task)
    else
      {:error, {:provider_unavailable, provider}}
    end
  end

  defp build_task(%Task{} = task), do: task

  defp build_task(params) when is_map(params) do
    Task.new(
      params[:input] || params["input"],
      type: params[:type] || params["type"],
      context: params[:context] || params["context"],
      language: params[:language] || params["language"],
      files: params[:files] || params["files"],
      metadata: params[:metadata] || params["metadata"]
    )
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini
end
