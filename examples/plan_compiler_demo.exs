Mix.Task.run("app.start")

alias Jido.Plan
alias Synapse.Actions.Echo
alias Synapse.PlanRunner
alias Synapse.Workflow.Spec

plan =
  Plan.new(context: %{tenant_id: "acme"})
  |> Plan.add(:echo, {Echo, %{message: "hello"}})
  |> Plan.add(:echo_again, {Echo, %{message: "world"}}, depends_on: :echo)

case PlanRunner.run(plan,
       name: :plan_demo,
       outputs: [Spec.output(:result, from: :echo_again, path: [:message])],
       input: %{},
       context: %{request_id: "req_plan_demo"}
     ) do
  {:ok, exec} ->
    IO.inspect(exec.outputs.result, label: "Plan result")

  {:error, failure} ->
    IO.inspect(failure.error, label: "Plan failed")
end
