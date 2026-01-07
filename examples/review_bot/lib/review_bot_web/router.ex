defmodule ReviewBotWeb.Router do
  use ReviewBotWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ReviewBotWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", ReviewBotWeb do
    pipe_through(:browser)

    live("/", ReviewLive.Index, :index)
    live("/reviews/new", ReviewLive.New, :new)
    live("/reviews/:id", ReviewLive.Show, :show)
  end

  # Other scopes may use custom stacks.
  # scope "/api", ReviewBotWeb do
  #   pipe_through :api
  # end
end
