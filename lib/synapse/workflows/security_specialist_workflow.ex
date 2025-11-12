defmodule Synapse.Workflows.SecuritySpecialistWorkflow do
  @moduledoc """
  Executes the security specialist action suite via `Synapse.Workflow.Engine`
  so each run benefits from telemetry, audit trails, and optional persistence.
  """

  alias Synapse.Actions.Security.{CheckAuthIssues, CheckSQLInjection, CheckXSS}
  alias Synapse.Workflow.{Engine, Spec}
  alias Synapse.Workflow.Spec.Step
  alias Synapse.Workflows.ChainHelpers

  @actions [CheckSQLInjection, CheckXSS, CheckAuthIssues]

  @type input :: %{
          required(:diff) => String.t(),
          required(:files) => [String.t()],
          optional(:metadata) => map()
        }

  @spec evaluate(input(), keyword()) :: {:ok, %{results: [map()]}} | {:error, Jido.Error.t()}
  def evaluate(params, opts \\ [])

  def evaluate(params, opts) when is_map(params) do
    context =
      opts
      |> Keyword.get(:context, %{})
      |> ensure_context()

    exec_opts =
      [input: params, context: context]
      |> maybe_put_persistence(opts)

    case Engine.execute(spec(), exec_opts) do
      {:ok, exec} ->
        {:ok, %{results: normalize_results(exec.results)}}

      {:error, failure} ->
        {:error, failure.error}
    end
  end

  def evaluate(_invalid, _opts), do: {:error, Jido.Error.validation_error("invalid params")}

  defp maybe_put_persistence(opts, opts_list) do
    case Keyword.get(opts_list, :persistence) do
      nil -> opts
      value -> Keyword.put(opts, :persistence, value)
    end
  end

  defp ensure_context(%{} = context) do
    Map.put_new(context, :request_id, ChainHelpers.generate_request_id())
  end

  defp ensure_context(_other) do
    %{request_id: ChainHelpers.generate_request_id()}
  end

  defp spec do
    steps =
      @actions
      |> Enum.with_index(1)
      |> Enum.map(fn {action, index} ->
        Step.new(
          id: :"action_#{index}",
          action: __MODULE__.StepRunner,
          label: Module.split(action) |> List.last(),
          params: fn env -> %{action: action, payload: env.input} end
        )
      end)

    Spec.new(
      name: :security_specialist_workflow,
      description: "Sequential security analysis (SQLi, XSS, auth)",
      metadata: %{version: 1},
      steps: steps,
      outputs: []
    )
  end

  defmodule StepRunner do
    @moduledoc false

    use Jido.Action,
      name: "security_step_runner",
      description: "Runs a security specialist action",
      schema: [
        action: [type: :atom, required: true],
        payload: [type: :map, default: %{}]
      ]

    alias Jido.Exec

    @impl true
    def run(%{action: action} = params, _context) do
      payload = Map.get(params, :payload, %{})

      case Exec.run(action, payload, %{}) do
        {:ok, result} -> {:ok, %{status: :ok, result: result}}
        {:error, error} -> {:ok, %{status: :error, error: error}}
      end
    end
  end

  defp normalize_results(results_map) do
    Enum.map(@actions |> Enum.with_index(1), fn {_action, index} ->
      case Map.get(results_map, :"action_#{index}") do
        %{status: :ok, result: result} -> result
        _ -> %{findings: [], confidence: 0.0}
      end
    end)
  end

  # no-op placeholder for backwards compatibility if needed in future
end
