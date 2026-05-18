defmodule SynapseWeb.Router do
  use SynapseWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SynapseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SynapseWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/runs", RunIndexLive, :index
    live "/runs/new", RunNewLive, :new
    live "/runs/:id", RunShowLive, :show
    live "/reviews", ReviewIndexLive, :index
    live "/reviews/:id", ReviewShowLive, :show
    live "/memory", MemoryIndexLive, :index
    live "/memory/:id", MemoryShowLive, :show
    live "/context-packs/:id", ContextPackShowLive, :show
    live "/tools", ToolIndexLive, :index
    live "/catalog", CatalogIndexLive, :index
    live "/catalog/:id", CatalogShowLive, :show
    live "/teams", TeamIndexLive, :index
    live "/teams/:id", TeamShowLive, :show
    live "/arbitration/:id", ArbitrationShowLive, :show
    live "/evidence", EvidenceIndexLive, :index
    live "/evidence/:id", EvidenceShowLive, :show
    live "/operations", OperationsLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", SynapseWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:synapse_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SynapseWeb.Telemetry
    end
  end
end
