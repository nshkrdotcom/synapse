defmodule Sample.Action do
  use Jido.Action,
    name: "sample_action",
    description: "Simple test action",
    schema: []

  @impl true
  def run(params, _context), do: {:ok, %{echo: params}}
end

defmodule Demo.Action do
  use Jido.Action,
    name: "demo_action",
    description: "Another test action",
    schema: []

  @impl true
  def run(params, _context), do: {:ok, %{demo: params}}
end

defmodule Runtime.Action do
  use Jido.Action,
    name: "runtime_action",
    description: "Runtime test action",
    schema: []

  @impl true
  def run(params, _context), do: {:ok, %{runtime: params}}
end
