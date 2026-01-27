defmodule Synapse.Signal.Ext.Context do
  @moduledoc """
  Signal extension for propagating NSAI Work/Plan context.
  """

  use Jido.Signal.Ext,
    namespace: "nsai",
    schema: [
      run_id: [type: :string, doc: "Run identifier"],
      work_id: [type: :string, doc: "Work/job identifier"],
      plan_id: [type: :string, doc: "Plan identifier"],
      step_id: [type: :string, doc: "Plan step identifier"],
      session_id: [type: :string, doc: "Session identifier"],
      actor_id: [type: :string, doc: "Actor identifier"],
      actor_type: [type: :string, doc: "Actor type"],
      tenant_id: [type: :string, doc: "Tenant identifier"]
    ]
end
