defmodule ReviewBot.Repo do
  use Ecto.Repo,
    otp_app: :review_bot,
    adapter: Ecto.Adapters.Postgres
end
