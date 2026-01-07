defmodule Synapse.Workflow.Persistence do
  @moduledoc """
  Behaviour + helpers for persisting workflow execution snapshots.

  Implementations (e.g., Postgres) store durable snapshots so workflows can be
  resumed after failures.
  """

  alias __MODULE__.Snapshot

  @type request_id :: String.t()

  @callback upsert_snapshot(Snapshot.t(), keyword()) :: :ok | {:error, term()}
  @callback get_snapshot(request_id(), keyword()) ::
              {:ok, Snapshot.t()} | {:error, :not_found | term()}
  @callback delete_snapshot(request_id(), keyword()) :: :ok | {:error, term()}

  @optional_callbacks get_snapshot: 2, delete_snapshot: 2

  defmodule Snapshot do
    @moduledoc """
    Snapshot payload used by persistence backends to store workflow progress.
    """

    @enforce_keys [
      :request_id,
      :spec_name,
      :spec_version,
      :status,
      :input,
      :context,
      :results,
      :audit_trail
    ]
    defstruct [
      :request_id,
      :spec_name,
      :spec_version,
      :status,
      :input,
      :context,
      :results,
      :audit_trail,
      :last_step_id,
      :last_attempt,
      :error
    ]

    @type t :: %__MODULE__{
            request_id: String.t(),
            spec_name: String.t(),
            spec_version: non_neg_integer(),
            status: atom() | String.t(),
            input: map(),
            context: map(),
            results: map(),
            audit_trail: map(),
            last_step_id: String.t() | nil,
            last_attempt: non_neg_integer() | nil,
            error: map() | nil
          }
  end
end
