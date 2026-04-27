defmodule EmisintWeb.Router do
  use EmisintWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  def put_session_timezone(conn, _opts) do
    timezone = conn.cookies["timezone"]
    put_session(conn, "timezone", timezone)
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmisintWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug EmisintWeb.SetTenant
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Emisint.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false
  end

  pipeline :mcp do
    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Emisint.Accounts.User,
      # Use `required?: false` to allow unauthenticated
      # users to connect, for example if some tools
      # are publicly accessible.
      required?: false
  end

  scope "/", EmisintWeb do
    pipe_through :browser

    ash_authentication_live_session :pending_routes,
      on_mount: [{EmisintWeb.LiveUserAuth, :live_user_required}] do
      live "/chat", ChatLive
      live "/chat/:conversation_id", ChatLive
      live "/pending", PendingLive, :index
      live "/admin/context", Admin.OrgContextLive, :index
      live "/admin/organizations", Admin.OrganizationsLive, :index
      live "/admin/organizations/:id", Admin.OrganizationShowLive, :show
      live "/admin/users", Admin.UsersLive, :index
    end

    post "/admin/context", Admin.OrgContextController, :set

    ash_authentication_live_session :authenticated_routes,
      on_mount: [
        {EmisintWeb.LiveUserAuth, :live_user_required},
        EmisintWeb.LiveScope
      ] do
      live "/dashboard", Dashboard.PortfolioLive, :index
      live "/admin/import", Admin.DataImportLive, :index
      live "/admin/import/history", Admin.ImportHistoryLive, :index
      live "/settings", SettingsLive, :index
      live "/mde", Mde.OverviewLive, :index
      live "/mde/districts/:district_code", Mde.DistrictAnalysisLive, :index
      live "/mde/entities", Mde.EntityMasterLive, :index
    end

    get "/mde/lea-comparison.pdf", MdeLeaReportController, :show
    get "/dashboard/portfolio.pdf", PortfolioReportController, :show
    get "/admin/import/errors/download", ErrorFileDownloadController, :download
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [:list_mde_isds],
      # For many tools, you will need to set the `protocol_version_statement` to the older version.
      protocol_version_statement: "2024-11-05",
      otp_app: :my_app
  end

  scope "/", EmisintWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, Emisint.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{EmisintWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    EmisintWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  EmisintWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Emisint.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [EmisintWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Emisint.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [EmisintWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", EmisintWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:emisint, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EmisintWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:emisint, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
