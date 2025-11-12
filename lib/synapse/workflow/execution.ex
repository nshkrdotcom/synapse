defmodule Synapse.Workflow.Execution do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "workflow_executions" do
    field(:request_id, :string)
    field(:spec_name, :string)
    field(:spec_version, :integer)
    field(:status, :string)
    field(:input, :map)
    field(:context, :map)
    field(:results, :map)
    field(:audit_trail, :map)
    field(:last_step_id, :string)
    field(:last_attempt, :integer)
    field(:error, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(request_id spec_name spec_version status input context results audit_trail last_step_id last_attempt error)a

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @fields)
    |> validate_required([
      :request_id,
      :spec_name,
      :spec_version,
      :status,
      :input,
      :context,
      :results,
      :audit_trail
    ])
  end
end
