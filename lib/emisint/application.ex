defmodule Emisint.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EmisintWeb.Telemetry,
      Emisint.Repo,
      {DNSCluster, query: Application.get_env(:emisint, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:emisint, :ash_domains),
         Application.fetch_env!(:emisint, Oban)
       )},
      {Phoenix.PubSub, name: Emisint.PubSub},
      # Start a worker by calling: Emisint.Worker.start_link(arg)
      # {Emisint.Worker, arg},
      # Start to serve requests, typically the last entry
      EmisintWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :emisint]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Emisint.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmisintWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
