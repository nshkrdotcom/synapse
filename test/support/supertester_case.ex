defmodule Synapse.SupertesterCase do
  @moduledoc """
  Shared test case that wires up Supertester isolation and helpers across the suite.
  """

  defmacro __using__(opts \\ []) do
    async? = Keyword.get(opts, :async, true)
    isolation = Keyword.get(opts, :isolation, default_isolation(async?))

    quote do
      use ExUnit.Case, async: unquote(async?)
      use Supertester.UnifiedTestFoundation, isolation: unquote(isolation)

      setup tags do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Synapse.Repo)

        unless tags[:async] do
          Ecto.Adapters.SQL.Sandbox.mode(Synapse.Repo, {:shared, self()})
        end

        :ok
      end

      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.SupervisorHelpers
      import Supertester.Assertions
      import Supertester.PerformanceHelpers
      import Supertester.ChaosHelpers
    end
  end

  defp default_isolation(_), do: :basic
end
