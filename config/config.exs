# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :smart_sort,
  ecto_repos: [SmartSort.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :smart_sort, SmartSortWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SmartSortWeb.ErrorHTML, json: SmartSortWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SmartSort.PubSub,
  live_view: [signing_salt: "QbeZ8sdO"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :smart_sort, SmartSort.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  smart_sort: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  smart_sort: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly",
         access_type: "offline",
         prompt: "consent",
         include_granted_scopes: true
       ]}
  ]

config :smart_sort, Oban,
  repo: SmartSort.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/30 * * * *", SmartSort.Jobs.RefreshGoogleTokens}
     ]}
  ],
  queues: [
    default: 2,
    scheduled: 2,
    renew_gmail_watches: 2
  ]

config :wallaby,
  driver: Wallaby.Chrome,
  screenshot_dir: "screenshots/wallaby",
  hackney_options: [timeout: 60_000, recv_timeout: 60_000],
  chrome_options: [
    headless: true,
    no_sandbox: true,
    disable_gpu: true,
    disable_dev_shm_usage: true,
    disable_background_timer_throttling: true,
    disable_backgrounding_occluded_windows: true,
    disable_renderer_backgrounding: true,
    disable_default_apps: true,
    disable_extensions: true,
    disable_plugins: true,
    disable_sync: true,
    disable_translate: true,
    disable_web_security: true,
    disable_feature: "TranslateUI",
    disable_feature: "BlinkGenPropertyTrees",
    disable_feature: "VizDisplayCompositor",
    user_data_dir: "/tmp/chrome-user-data",
    crash_dumps_dir: "/tmp/chrome-crashes"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
