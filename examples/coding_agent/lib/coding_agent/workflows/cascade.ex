defmodule CodingAgent.Workflows.Cascade do
  @moduledoc """
  Try providers in order, falling back on failure.

  This workflow attempts each provider in sequence until one succeeds.
  Useful for reliability when you want guaranteed results even if
  some providers are unavailable or failing.
  """

  alias CodingAgent.{Task, Providers}

  @doc """
  Run a task with fallback chain.

  Tries each provider in order until one succeeds.
  Returns `{:ok, result}` with the first successful result,
  or `{:error, :all_providers_failed}` if all fail.
  """
  @spec run(Task.t(), [atom()]) :: {:ok, map()} | {:error, :all_providers_failed}
  def run(%Task{} = task, providers) when is_list(providers) do
    Enum.reduce_while(providers, {:error, :all_providers_failed}, fn provider, _acc ->
      module = resolve_provider(provider)

      if module.available?() do
        case module.execute(task) do
          {:ok, result} ->
            # Add cascade metadata
            result_with_meta =
              result
              |> Map.put(:cascade_position, Enum.find_index(providers, &(&1 == provider)) + 1)
              |> Map.put(:cascade_provider, provider)
              |> Map.put(:cascade_total, length(providers))

            {:halt, {:ok, result_with_meta}}

          {:error, _reason} ->
            {:cont, {:error, :all_providers_failed}}
        end
      else
        {:cont, {:error, :all_providers_failed}}
      end
    end)
  end

  defp resolve_provider(:claude), do: Providers.Claude
  defp resolve_provider(:codex), do: Providers.Codex
  defp resolve_provider(:gemini), do: Providers.Gemini
end
