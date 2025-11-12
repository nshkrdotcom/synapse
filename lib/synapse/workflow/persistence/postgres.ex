defmodule Synapse.Workflow.Persistence.Postgres do
  @moduledoc """
  Postgres-backed persistence adapter for workflow snapshots.
  """

  @behaviour Synapse.Workflow.Persistence

  import Ecto.Query

  alias Synapse.Repo
  alias Synapse.Workflow.Execution
  alias Synapse.Workflow.Persistence.Snapshot

  @impl true
  def upsert_snapshot(%Snapshot{} = snapshot, _opts) do
    changeset = Execution.changeset(%Execution{}, normalize_snapshot(snapshot))

    case Repo.insert(changeset,
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: :request_id
         ) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def get_snapshot(request_id, _opts) do
    case Repo.get_by(Execution, request_id: request_id) do
      nil -> {:error, :not_found}
      execution -> {:ok, to_snapshot(execution)}
    end
  end

  @impl true
  def delete_snapshot(request_id, _opts) do
    {count, _} = Repo.delete_all(from(e in Execution, where: e.request_id == ^request_id))

    if count > 0, do: :ok, else: {:error, :not_found}
  end

  defp normalize_snapshot(snapshot) do
    %{
      request_id: snapshot.request_id,
      spec_name: snapshot.spec_name |> to_string(),
      spec_version: snapshot.spec_version,
      status: normalize_status(snapshot.status),
      input: snapshot.input || %{},
      context: snapshot.context || %{},
      results: snapshot.results || %{},
      audit_trail: snapshot.audit_trail || %{},
      last_step_id: snapshot.last_step_id,
      last_attempt: snapshot.last_attempt,
      error: snapshot.error
    }
  end

  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(status) when is_binary(status), do: status

  defp to_snapshot(execution) do
    %Snapshot{
      request_id: execution.request_id,
      spec_name: execution.spec_name,
      spec_version: execution.spec_version,
      status: execution.status,
      input: execution.input,
      context: execution.context,
      results: execution.results,
      audit_trail: execution.audit_trail,
      last_step_id: execution.last_step_id,
      last_attempt: execution.last_attempt,
      error: execution.error
    }
  end
end
