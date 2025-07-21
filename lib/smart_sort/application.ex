defmodule SmartSort.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SmartSortWeb.Telemetry,
      SmartSort.Repo,
      {DNSCluster, query: Application.get_env(:smart_sort, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SmartSort.PubSub},
      # Start a worker by calling: SmartSort.Worker.start_link(arg)
      # {SmartSort.Worker, arg},
      # Start to serve requests, typically the last entry
      {Oban, oban_config()},
      SmartSortWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SmartSort.Supervisor]
    result = Supervisor.start_link(children, opts)

    Task.start(fn ->
      :timer.sleep(2000)
      SmartSort.GmailAccountHandler.start_all_gmail_notifications()
    end)

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SmartSortWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    Application.fetch_env!(:smart_sort, Oban)
  end
end
