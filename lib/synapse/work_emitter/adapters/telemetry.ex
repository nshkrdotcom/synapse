defmodule Synapse.WorkEmitter.Adapters.Telemetry do
  @moduledoc false

  @behaviour Synapse.WorkEmitter.Adapter

  @impl true
  def emit(:started, job, _opts) do
    Work.Telemetry.job_started(job)
    :ok
  end

  def emit(:succeeded, job, _opts) do
    Work.Telemetry.job_completed(job)
    :ok
  end

  def emit(:failed, job, _opts) do
    Work.Telemetry.job_completed(job)
    :ok
  end

  def emit(:canceled, job, _opts) do
    Work.Telemetry.job_canceled(job)
    :ok
  end

  def emit(_event, _job, _opts), do: :ok
end
