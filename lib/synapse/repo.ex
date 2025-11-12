defmodule Synapse.Repo do
  use Ecto.Repo,
    otp_app: :synapse,
    adapter: Ecto.Adapters.Postgres
end
