defmodule Synapse.Examples.Stage2Demo do
  @moduledoc """
  Stage 2 Demo showcasing the declarative orchestrator runtime.

  Invokes the running runtime, publishes a review request, and prints the
  consolidated summary emitted by the declarative coordinator.
  """

  alias Synapse.SignalRouter

  @doc """
  Publishes a demo review request and prints the resulting summary.
  """
  def run(opts \\ []) do
    runtime = Keyword.get_lazy(opts, :runtime, &Synapse.Runtime.fetch/0)
    {:ok, sub_id} = SignalRouter.subscribe(runtime.router, :review_summary)

    review_id = "stage2_demo_#{System.unique_integer([:positive])}"

    {:ok, _} =
      SignalRouter.publish(
        runtime.router,
        :review_request,
        %{
          review_id: review_id,
          diff: demo_diff(),
          files_changed: 42,
          labels: ["security", "performance"],
          intent: "feature",
          risk_factor: 0.6,
          metadata: %{files: ["lib/critical.ex"], author: "stage2"}
        }
      )

    result =
      receive do
        {:signal, %Jido.Signal{type: "review.summary", data: data}} ->
          print_summary(data)
          {:ok, data}
      after
        5_000 ->
          IO.puts("Timed out waiting for review.summary")
          {:error, :timeout}
      end

    SignalRouter.unsubscribe(runtime.router, sub_id)
    result
  end

  @doc """
  Returns the current orchestrator health information.
  """
  def health_check(server \\ Synapse.Orchestrator.Runtime) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> Synapse.Orchestrator.Runtime.health_check(pid)
      _ -> %{total: 0, running: 0, failed: 0}
    end
  end

  defp demo_diff do
    """
    diff --git a/lib/critical.ex b/lib/critical.ex
    +defmodule Critical do
    +  def insecure(user_input) do
    +    query = "SELECT * FROM users WHERE id = '\#{user_input}'"
    +    Repo.query(query)
    +  end
    +
    +  def extreme_complexity(flag, acc) do
    +    if flag do
    +      if acc > 10 do
    +        if acc < 100 do
    +          if rem(acc, 2) == 0 do
    +            extreme_complexity(flag, acc + 1)
    +          else
    +            extreme_complexity(flag, acc + 2)
    +          end
    +        end
    +      end
    +    end
    +  end
    +end
    """
  end

  defp print_summary(summary) do
    IO.puts("\n=== Stage2 Summary ===")
    IO.puts("Review Summary: #{inspect(summary)}")
  end
end
