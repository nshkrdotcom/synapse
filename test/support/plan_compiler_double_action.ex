defmodule Synapse.TestSupport.PlanCompilerDoubleAction do
  @moduledoc false

  use Jido.Action,
    name: "plan_compiler_double",
    schema: [value: [type: :integer, required: true]]

  @impl true
  def run(params, _context) do
    {:ok, %{value: params.value * 2}}
  end
end
