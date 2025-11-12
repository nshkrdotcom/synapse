defmodule Synapse.Orchestrator.DeclarativeRuntimeTest do
  use Synapse.SupertesterCase, async: false

  import Synapse.TestSupport.RuntimeHelpers

  alias Synapse.Orchestrator.Runtime
  alias Synapse.SignalRouter

  @moduletag :capture_log

  setup context do
    setup_runtime(context,
      subscribe: [:review_summary, :review_result]
    )
  end

  test "coordinator orchestrates specialists to emit review summary", %{runtime: runtime} do
    config_path = Path.expand("../../../priv/orchestrator_agents.exs", __DIR__)

    {:ok, orchestrator} =
      start_supervised(
        {Runtime,
         config_source: config_path,
         router: runtime.router,
         registry: runtime.registry,
         reconcile_interval: 50,
         include_types: :all}
      )

    assert eventually(fn ->
             orchestrator
             |> Runtime.list_agents()
             |> Enum.map(& &1.agent_id)
             |> Enum.sort() == [:coordinator, :performance_specialist, :security_specialist]
           end)

    review_id = "dsl-coord-#{System.unique_integer([:positive])}"

    {:ok, _} =
      SignalRouter.publish(
        runtime.router,
        :review_request,
        %{
          review_id: review_id,
          diff: """
          def insecure(user_input) do
            query = "SELECT * FROM users WHERE email = '\#{user_input}'"
            Repo.query(query)
          end
          """,
          files_changed: 7,
          labels: ["security"],
          metadata: %{files: ["lib/sample.ex"]}
        }
      )

    summary = wait_for_summary(review_id, 5_000)
    assert summary.review_id == review_id
  end

  test "coordinator negotiation hook records conflicting findings", %{runtime: runtime} do
    config_path = Path.expand("../../../priv/orchestrator_agents.exs", __DIR__)

    {:ok, orchestrator} =
      start_supervised(
        {Runtime,
         config_source: config_path,
         router: runtime.router,
         registry: runtime.registry,
         reconcile_interval: 50,
         include_types: :all}
      )

    assert eventually(fn ->
             orchestrator
             |> Runtime.list_agents()
             |> Enum.map(& &1.agent_id)
             |> Enum.sort() == [:coordinator, :performance_specialist, :security_specialist]
           end)

    review_id = "dsl-coord-negotiation-#{System.unique_integer([:positive])}"

    diff_payload = """
    diff --git a/lib/vulnerable.ex b/lib/vulnerable.ex
    +defmodule Vulnerable do
    +  def insecure(user_input) do
    +    Repo.query("SELECT * FROM users WHERE email = '\#{user_input}'")
    +  end
    +end
    """

    {:ok, _} =
      SignalRouter.publish(
        runtime.router,
        :review_request,
        %{
          review_id: review_id,
          diff: diff_payload,
          files_changed: 1,
          labels: ["security"],
          metadata: %{files: ["lib/vulnerable.ex"]}
        }
      )

    summary = wait_for_summary(review_id, 5_000)
    refute summary.metadata[:negotiations] == []

    [%{agents: agents, winning_agent: winning, resolution: resolution}] =
      summary.metadata.negotiations

    assert Enum.sort(agents) == ["performance_specialist", "security_specialist"]
    assert winning == "security_specialist"
    assert resolution == :prefer_highest_severity
  end

  defp eventually(fun, retries \\ 40)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, retries) do
    if fun.() do
      true
    else
      Process.sleep(50)
      eventually(fun, retries - 1)
    end
  end

  defp wait_for_summary(review_id, timeout) do
    receive do
      {:signal, %Jido.Signal{type: "review.summary", data: %{review_id: ^review_id} = data}} ->
        data

      {:signal, _other} ->
        wait_for_summary(review_id, timeout)
    after
      timeout ->
        flunk("Did not receive review.summary for #{review_id}")
    end
  end
end
