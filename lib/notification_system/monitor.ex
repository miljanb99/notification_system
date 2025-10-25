defmodule NotificationSystem.Monitor do
  @moduledoc """
  Monitor GenServer prati performanse i health sistema.

  Funkcionalnosti:
  - Periodicno prikuplja statistiku
  - Detektuje probleme u sistemu
  - Loguje metrike
  """
  use GenServer
  require Logger

  @check_interval 30_000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Vraca trenutnu statistiku celog sistema
  """
  def system_stats do
    GenServer.call(__MODULE__, :system_stats)
  end

  # Server Callbacks

  @impl true
  def init(_) do
    # Zakazi periodicno prikupljanje statistike
    schedule_check()

    state = %{
      checks_performed: 0,
      last_check: nil
    }

    Logger.info("Monitor started on node: #{Node.self()}")
    {:ok, state}
  end

  @impl true
  def handle_call(:system_stats, _from, state) do
    stats = collect_stats()
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:check, state) do
    stats = collect_stats()
    log_stats(stats)

    # Zakazi sledecu proveru
    schedule_check()

    new_state = %{
      state
      | checks_performed: state.checks_performed + 1,
        last_check: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp collect_stats do
    broker_stats = NotificationSystem.Broker.stats()

    # Broj aktivnih subs
    subscriber_count = Registry.count(NotificationSystem.Registry)

    # Broj nodes u klasteru
    nodes = [Node.self() | Node.list()]

    %{
      broker: broker_stats,
      subscribers: subscriber_count,
      nodes: nodes,
      node_count: length(nodes),
      timestamp: DateTime.utc_now()
    }
  end

  defp log_stats(stats) do
    Logger.info("""
    === System Statistics ===
    Node: #{stats.broker.node}
    Messages sent: #{stats.broker.messages_sent}
    Active subs: #{stats.subscribers}
    Nodes in Cluster: #{stats.node_count}
    Uptime: #{stats.broker.uptime_seconds}s
    ========================
    """)
  end
end
