Mix.Task.run("app.start")

case Synapse.Examples.Stage2Demo.run() do
  {:ok, _summary} ->
    IO.puts("\nStage2 Demo completed successfully.")

  {:error, reason} ->
    Mix.raise("Stage2Demo failed: #{inspect(reason)}")
end
