defmodule Synapse.TestSupport.PlanCompilerFetchAction do
  @moduledoc false

  use Jido.Action,
    name: "plan_compiler_fetch",
    schema: [value: [type: :integer, required: true]]

  @impl true
  def run(params, _context) do
    {:ok, %{value: params.value}}
  end
end
