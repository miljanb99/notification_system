defmodule NotificationSystem.Broker do
  @moduledoc """
  Centralni broker za distribuciju notifikacija pretplatnicima.
  """
  use GenServer
  require Logger

  @registry NotificationSystem.Registry

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def publish(topic, message, opts \\ []) do
    GenServer.cast(__MODULE__, {:publish, topic, message, opts})
  end

  def broadcast(message) do
    GenServer.cast(__MODULE__, {:broadcast, message})
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_) do
    state = %{
      messages_sent: 0,
      started_at: DateTime.utc_now()
    }
    Logger.info("Broker pokrenut na nodu: #{Node.self()}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:publish, topic, message}, state) do
    handle_cast({:publish, topic, message, []}, state)
  end

  @impl true
  def handle_cast({:publish, topic, message, opts}, state) do
    Logger.debug("Publishing message to topic: #{topic}")

    case NotificationSystem.RateLimiter.check_rate(topic) do
      {:error, :rate_limited} ->
        Logger.warn("Message rate limited for topic: #{topic}")
        NotificationSystem.Metrics.record_error(:rate_limited, topic)
        {:noreply, state}

      {:ok, :allowed} ->
        persist = Keyword.get(opts, :persist, false)
        priority = Keyword.get(opts, :priority, 5)

        message_id = if persist do
          case NotificationSystem.Persistence.store_message(topic, message, priority: priority) do
            {:ok, id} -> id
            {:error, _} -> nil
          end
        else
          nil
        end

        NotificationSystem.Metrics.record_publish(topic)
        publish_time = System.monotonic_time(:microsecond)
        use_router = Keyword.get(opts, :use_router, false)

        if use_router do
          NotificationSystem.Router.route_message(topic, message, priority: priority)
        else
          subscribers = Registry.lookup(@registry, topic)

          Enum.each(subscribers, fn {pid, _value} ->
            send(pid, {:notification, topic, message, publish_time})

            if message_id do
              NotificationSystem.Acknowledgment.track_message(message_id, topic, message)
            end
          end)

          NotificationSystem.Metrics.record_delivery(topic, 0)
        end

        new_state = %{state | messages_sent: state.messages_sent + 1}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    Logger.debug("Broadcasting message to all subscribers")

    topics = Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()

    Enum.each(topics, fn topic ->
      subscribers = Registry.lookup(@registry, topic)
      Enum.each(subscribers, fn {pid, _value} ->
        send(pid, {:notification, :broadcast, message})
      end)
    end)

    new_state = %{state | messages_sent: state.messages_sent + 1}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_subscribers = Registry.count(@registry)
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)

    stats = %{
      node: Node.self(),
      messages_sent: state.messages_sent,
      total_subscribers: total_subscribers,
      uptime_seconds: uptime_seconds,
      started_at: state.started_at
    }

    {:reply, stats, state}
  end
end
