defmodule Synapse.SupertesterCase do
  @moduledoc """
  Shared test case that wires up Supertester isolation and helpers across the suite.
  """

  defmacro __using__(opts \\ []) do
    async? = Keyword.get(opts, :async, true)
    isolation = Keyword.get(opts, :isolation, :basic)

    quote do
      use ExUnit.Case, async: unquote(async?)

      alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox
      alias Supertester.UnifiedTestFoundation, as: UnifiedTestFoundation

      setup tags do
        # Setup Supertester isolation
        {:ok, base_context} =
          UnifiedTestFoundation.setup_isolation(unquote(isolation), tags)

        # Setup Ecto sandbox
        :ok = SQLSandbox.checkout(Synapse.Repo)

        unless tags[:async] do
          SQLSandbox.mode(Synapse.Repo, {:shared, self()})
        end

        {:ok, base_context}
      end

      import Supertester.OTPHelpers
      import Supertester.GenServerHelpers
      import Supertester.SupervisorHelpers
      import Supertester.Assertions
      import Supertester.PerformanceHelpers
      import Supertester.ChaosHelpers
    end
  end
end
