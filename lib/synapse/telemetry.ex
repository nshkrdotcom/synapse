defmodule Synapse.Telemetry do
  @moduledoc """
  Telemetry event emission for Synapse system monitoring.

  Provides structured telemetry events for tracking LLM operations,
  compensation events, and system health.

  ## Events

  ### LLM Compensation: `[:synapse, :llm, :compensation]`

  Emitted when an LLM request fails and compensation is triggered.

  **Measurements:**
  - `:system_time` - System time when compensation occurred

  **Metadata:**
  - `:request_id` - Unique request identifier for tracking
  - `:profile` - LLM profile name (e.g., :openai, :gemini)
  - `:error_type` - Type of error that triggered compensation

  ## Usage

      # Emit compensation event
      Synapse.Telemetry.emit_compensation(
        request_id: "req_123",
        profile: :openai,
        error_type: :execution_error
      )

  ## Attaching Handlers

      :telemetry.attach(
        "my-handler",
        [:synapse, :llm, :compensation],
        fn _event, measurements, metadata, _config ->
          # Handle the event
          Logger.warning("LLM compensation",
            request_id: metadata.request_id,
            profile: metadata.profile
          )
        end,
        nil
      )
  """

  require Logger

  @orchestrator_summary_event [:synapse, :workflow, :orchestrator, :summary]
  @orchestrator_handler_id "synapse-orchestrator-summary-logger"

  @doc """
  Emits a telemetry event for LLM compensation.

  ## Parameters

    * `opts` - Keyword list with:
      - `:request_id` - Unique request identifier
      - `:profile` - LLM profile name
      - `:error_type` - Type of error

  ## Examples

      Synapse.Telemetry.emit_compensation(
        request_id: "req_123",
        profile: :openai,
        error_type: :execution_error
      )
  """
  @spec emit_compensation(keyword()) :: :ok
  def emit_compensation(opts) do
    request_id = Keyword.get(opts, :request_id, "unknown")
    profile = Keyword.get(opts, :profile, "unknown")
    error_type = Keyword.get(opts, :error_type, :unknown)

    :telemetry.execute(
      [:synapse, :llm, :compensation],
      %{system_time: System.system_time()},
      %{
        request_id: request_id,
        profile: profile,
        error_type: error_type
      }
    )

    :ok
  end

  @doc """
  Emits telemetry when a coordinator replays a review request directly to a newly spawned specialist.
  """
  @spec emit_specialist_replay(keyword()) :: :ok
  def emit_specialist_replay(opts) do
    :telemetry.execute(
      [:synapse, :specialist, :replay],
      %{system_time: System.system_time()},
      %{
        specialist: Keyword.get(opts, :specialist),
        review_id: Keyword.get(opts, :review_id),
        bus: Keyword.get(opts, :bus)
      }
    )

    :ok
  end

  @doc """
  Emits telemetry when a specialist crashes before completing a review.
  """
  @spec emit_specialist_crash(keyword()) :: :ok
  def emit_specialist_crash(opts) do
    :telemetry.execute(
      [:synapse, :specialist, :crash],
      %{system_time: System.system_time()},
      %{
        specialist: Keyword.get(opts, :specialist),
        review_id: Keyword.get(opts, :review_id),
        reason: Keyword.get(opts, :reason)
      }
    )

    :ok
  end

  @doc """
  Installs the orchestrator summary telemetry handler that logs coordinator outcomes.

  Options:
    * `:handler_id` - override the telemetry handler id
    * `:log?` - disable logging when attaching custom handlers (defaults to true)
  """
  @spec attach_orchestrator_summary_handler(keyword()) :: :ok
  def attach_orchestrator_summary_handler(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @orchestrator_handler_id)
    config = %{log?: Keyword.get(opts, :log?, true)}

    case :telemetry.attach_many(
           handler_id,
           [@orchestrator_summary_event],
           &__MODULE__.handle_orchestrator_summary/4,
           config
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc """
  Detaches the orchestrator summary telemetry handler.
  """
  @spec detach_orchestrator_summary_handler(keyword()) :: :ok
  def detach_orchestrator_summary_handler(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @orchestrator_handler_id)
    :telemetry.detach(handler_id)
    :ok
  rescue
    _ -> :ok
  end

  def handle_orchestrator_summary(_event, _measurements, _metadata, %{log?: false}), do: :ok

  def handle_orchestrator_summary(_event, measurements, metadata, _config) do
    specialists =
      metadata
      |> Map.get(:specialists, [])
      |> List.wrap()

    negotiators =
      metadata
      |> Map.get(:negotiations, [])
      |> List.wrap()

    Logger.info("Orchestrator summary emitted",
      config_id: Map.get(metadata, :config_id),
      review_id: Map.get(metadata, :review_id),
      status: Map.get(metadata, :status),
      severity: Map.get(metadata, :severity),
      decision_path: Map.get(metadata, :decision_path),
      duration_ms: Map.get(measurements, :duration_ms, 0),
      finding_count: Map.get(measurements, :finding_count, 0),
      recommendation_count: Map.get(measurements, :recommendation_count, 0),
      specialists: specialists,
      escalation_count: metadata |> Map.get(:escalations, []) |> Enum.count(),
      negotiation_count: Enum.count(negotiators)
    )
  end
end
