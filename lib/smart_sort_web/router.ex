defmodule SmartSortWeb.Router do
  use SmartSortWeb, :router

  import SmartSortWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SmartSortWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # scope "/", SmartSortWeb do
  #   pipe_through :browser

  #   get "/", PageController, :home
  # end

  scope "/auth", SmartSortWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/add-account", AuthController, :add_account
  end

  scope "/auth", SmartSortWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", SmartSortWeb do
    pipe_through [:browser]

    live "/", LandingLive

    pipe_through [:require_authenticated_user]

    live "/dashboard", DashboardLive
    live "/categories/:category_id/emails", EmailsLive

    get "/logout", AuthController, :logout_user
  end

  scope "/webhooks", SmartSortWeb do
    pipe_through :api
    post "/gmail", GmailWebhookController, :receive
  end

  # Other scopes may use custom stacks.
  # scope "/api", SmartSortWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:smart_sort, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SmartSortWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
