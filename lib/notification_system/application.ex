defmodule NotificationSystem.Application do
  @moduledoc """
  Glavna aplikacija koja pokrece supervision tree.
  Koristi OTP principe za toleranciju gresaka i konkurentnost.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Inicijalizacija sloja za perzistenciju...")
    NotificationSystem.Persistence.init()

    children = [
      {Registry, keys: :duplicate, name: NotificationSystem.Registry},
      {NotificationSystem.RateLimiter, [global_rate: 10_000, global_burst: 1000]},
      NotificationSystem.Metrics,
      NotificationSystem.Router,
      NotificationSystem.Broker,
      NotificationSystem.Acknowledgment,
      NotificationSystem.DeadLetterQueue,
      {DynamicSupervisor, name: NotificationSystem.SubscriberSupervisor, strategy: :one_for_one},
      NotificationSystem.Monitor
    ]

    opts = [strategy: :one_for_one, name: NotificationSystem.Supervisor]
    Logger.info("Pokretanje NotificationSystem-a...")
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    Logger.info("Zaustavljanje NotificationSystem-a...")
    :ok
  end
end
