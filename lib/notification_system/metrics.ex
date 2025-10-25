defmodule NotificationSystem.Metrics do
  @moduledoc """
  Sistem za prikupljanje i izvestavanje metrika.

  Pruza:
  - Metrike performansi u realnom vremenu
  - Praćcnje protoka poruka
  - Merenje kasnjenja
  - Error rate monitoring
  - Prometheus-compatible export format
  """
  use GenServer
  require Logger

  @collect_interval 10_000  # 10 seconds

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Belezi event objavljivanja poruke
  """
  def record_publish(topic) do
    GenServer.cast(__MODULE__, {:record_publish, topic, System.monotonic_time(:microsecond)})
  end

  @doc """
  Belezi event isporuke poruke
  """
  def record_delivery(topic, latency_us) do
    GenServer.cast(__MODULE__, {:record_delivery, topic, latency_us})
  end

  @doc """
  Belezi error event
  """
  def record_error(type, reason) do
    GenServer.cast(__MODULE__, {:record_error, type, reason})
  end

  @doc """
  Dohvatanje trenutnih metrika
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Dohvatanje metrika u Prometheus formatu eksplozije
  """
  def prometheus_format do
    GenServer.call(__MODULE__, :prometheus_format)
  end

  @doc """
  Resetovanje svih metrika
  """
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_collection()

    state = %{
      publishes: %{},           # topic => count
      deliveries: %{},          # topic => count
      errors: %{},              # type => count
      latencies: [],            # list of latency measurements
      throughput_history: [],   # historical throughput data
      start_time: DateTime.utc_now(),
      last_collection: DateTime.utc_now()
    }

    Logger.info("Metrics collection started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_publish, topic, _timestamp}, state) do
    publishes = Map.update(state.publishes, topic, 1, &(&1 + 1))
    {:noreply, %{state | publishes: publishes}}
  end

  @impl true
  def handle_cast({:record_delivery, topic, latency_us}, state) do
    deliveries = Map.update(state.deliveries, topic, 1, &(&1 + 1))

    # Cuva poslednjih 1000 latency merenja
    latencies = [latency_us | state.latencies] |> Enum.take(1000)

    {:noreply, %{state | deliveries: deliveries, latencies: latencies}}
  end

  @impl true
  def handle_cast({:record_error, type, _reason}, state) do
    errors = Map.update(state.errors, type, 1, &(&1 + 1))
    {:noreply, %{state | errors: errors}}
  end

  @impl true
  def handle_cast(:reset, state) do
    new_state = %{
      state |
      publishes: %{},
      deliveries: %{},
      errors: %{},
      latencies: [],
      start_time: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:prometheus_format, _from, state) do
    metrics = calculate_metrics(state)
    prometheus_text = format_prometheus(metrics)
    {:reply, prometheus_text, state}
  end

  @impl true
  def handle_info(:collect, state) do
    # Prikuplja snapshot propusnosti
    total_publishes = state.publishes |> Map.values() |> Enum.sum()
    timestamp = DateTime.utc_now()

    throughput_snapshot = %{
      timestamp: timestamp,
      total_messages: total_publishes
    }

    # Cuva 1000 takvih
    throughput_history = [throughput_snapshot | state.throughput_history]
      |> Enum.take(100)

    schedule_collection()
    {:noreply, %{state | throughput_history: throughput_history, last_collection: timestamp}}
  end

  # Private functions

  defp calculate_metrics(state) do
    total_publishes = state.publishes |> Map.values() |> Enum.sum()
    total_deliveries = state.deliveries |> Map.values() |> Enum.sum()
    total_errors = state.errors |> Map.values() |> Enum.sum()

    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    latency_stats = if length(state.latencies) > 0 do
      sorted = Enum.sort(state.latencies)
      count = length(sorted)

      %{
        min: Enum.min(sorted) / 1000,
        max: Enum.max(sorted) / 1000,
        avg: Enum.sum(sorted) / count / 1000,
        p50: percentile(sorted, 0.5) / 1000,
        p95: percentile(sorted, 0.95) / 1000,
        p99: percentile(sorted, 0.99) / 1000
      }
    else
      %{min: 0, max: 0, avg: 0, p50: 0, p95: 0, p99: 0}
    end

    throughput = if uptime_seconds > 0 do
      total_publishes / uptime_seconds
    else
      0.0
    end

    %{
      total_publishes: total_publishes,
      total_deliveries: total_deliveries,
      total_errors: total_errors,
      publishes_by_topic: state.publishes,
      deliveries_by_topic: state.deliveries,
      errors_by_type: state.errors,
      latency_ms: latency_stats,
      throughput_per_second: Float.round(throughput, 2),
      uptime_seconds: uptime_seconds,
      delivery_rate: calculate_delivery_rate(total_publishes, total_deliveries),
      error_rate: calculate_error_rate(total_publishes, total_errors)
    }
  end

  defp percentile(sorted_list, percentile) do
    count = length(sorted_list)
    index = round(percentile * count) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_list, index)
  end

  defp calculate_delivery_rate(publishes, deliveries) do
    if publishes > 0 do
      Float.round(deliveries / publishes * 100, 2)
    else
      0.0
    end
  end

  defp calculate_error_rate(publishes, errors) do
    if publishes > 0 do
      Float.round(errors / publishes * 100, 2)
    else
      0.0
    end
  end

  defp format_prometheus(metrics) do
    """
    # HELP notification_system_publishes_total Total number of published messages
    # TYPE notification_system_publishes_total counter
    notification_system_publishes_total #{metrics.total_publishes}

    # HELP notification_system_deliveries_total Total number of delivered messages
    # TYPE notification_system_deliveries_total counter
    notification_system_deliveries_total #{metrics.total_deliveries}

    # HELP notification_system_errors_total Total number of errors
    # TYPE notification_system_errors_total counter
    notification_system_errors_total #{metrics.total_errors}

    # HELP notification_system_latency_milliseconds Message delivery latency
    # TYPE notification_system_latency_milliseconds summary
    notification_system_latency_milliseconds{quantile="0.5"} #{metrics.latency_ms.p50}
    notification_system_latency_milliseconds{quantile="0.95"} #{metrics.latency_ms.p95}
    notification_system_latency_milliseconds{quantile="0.99"} #{metrics.latency_ms.p99}
    notification_system_latency_milliseconds_sum #{metrics.latency_ms.avg * metrics.total_deliveries}
    notification_system_latency_milliseconds_count #{metrics.total_deliveries}

    # HELP notification_system_throughput_per_second Current message throughput
    # TYPE notification_system_throughput_per_second gauge
    notification_system_throughput_per_second #{metrics.throughput_per_second}

    # HELP notification_system_delivery_rate_percent Percentage of successfully delivered messages
    # TYPE notification_system_delivery_rate_percent gauge
    notification_system_delivery_rate_percent #{metrics.delivery_rate}

    # HELP notification_system_error_rate_percent Percentage of messages with errors
    # TYPE notification_system_error_rate_percent gauge
    notification_system_error_rate_percent #{metrics.error_rate}

    # HELP notification_system_uptime_seconds System uptime in seconds
    # TYPE notification_system_uptime_seconds counter
    notification_system_uptime_seconds #{metrics.uptime_seconds}
    """
  end

  defp schedule_collection do
    Process.send_after(self(), :collect, @collect_interval)
  end
end
