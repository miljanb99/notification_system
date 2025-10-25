defmodule NotificationSystem.Subscriber do
  @moduledoc """
  Subscriber GenServer koji se registruje za odredjene teme i prima notifikacije

  Svaki subscriber je nezavisan proces koji:
  - Registruje za jednu ili vise tema (topic)
  - Prima i procesira poruke
  - Moze biti restartovan u slucaju greske (fault tolerance)
  """
  use GenServer
  require Logger

  @registry NotificationSystem.Registry

  # Client API

  @doc """
  Pokrece novog subscribera sa konfiguracijom.

  Opcije:
  - :name - ime subscribera
  - :topics - lista tema za praćenje
  - :handler - funkcija za procesiranje poruka
  """
  def start_link(opts) do
    # Don't use :via tuple with duplicate registry - just start the GenServer normally
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Dodaje novu temu za pracenje
  """
  def subscribe(subscriber, topic) do
    GenServer.call(subscriber, {:subscribe, topic})
  end

  @doc """
  Uklanja temu iz pracenja
  """
  def unsubscribe(subscriber, topic) do
    GenServer.call(subscriber, {:unsubscribe, topic})
  end

  @doc """
  Vraca statistiku subscribera.
  """
  def stats(subscriber) do
    GenServer.call(subscriber, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, generate_name())
    topics = Keyword.get(opts, :topics, [])
    handler = Keyword.get(opts, :handler, &default_handler/2)

    state = %{
      name: name,
      topics: MapSet.new(),
      handler: handler,
      messages_received: 0,
      started_at: DateTime.utc_now()
    }

    # Registruj se za pocetne topic-e
    new_state = Enum.reduce(topics, state, fn topic, acc ->
      register_topic(topic)
      %{acc | topics: MapSet.put(acc.topics, topic)}
    end)

    Logger.info("Subscriber '#{name}' pokrenut na nodu: #{Node.self()}")
    {:ok, new_state}
  end

  @impl true
  def handle_call({:subscribe, topic}, _from, state) do
    if MapSet.member?(state.topics, topic) do
      {:reply, {:error, :already_subscribed}, state}
    else
      register_topic(topic)
      new_topics = MapSet.put(state.topics, topic)
      Logger.info("Subscriber '#{state.name}' subscribed to topic: #{topic}")
      {:reply, :ok, %{state | topics: new_topics}}
    end
  end

  @impl true
  def handle_call({:unsubscribe, topic}, _from, state) do
    if MapSet.member?(state.topics, topic) do
      unregister_topic(topic)
      new_topics = MapSet.delete(state.topics, topic)
      Logger.info("Subscriber '#{state.name}' unsubscribed from topic: #{topic}")
      {:reply, :ok, %{state | topics: new_topics}}
    else
      {:reply, {:error, :not_subscribed}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)

    stats = %{
      name: state.name,
      node: Node.self(),
      topics: MapSet.to_list(state.topics),
      messages_received: state.messages_received,
      uptime_seconds: uptime_seconds,
      started_at: state.started_at
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:notification, topic, message}, state) do
    process_notification(topic, message, state)
  end

  @impl true
  def handle_info({:notification, topic, message, _timestamp}, state) do
    process_notification(topic, message, state)
  end

  # Private Functions

  defp process_notification(topic, message, state) do
    Logger.debug("Subscriber '#{state.name}' received message on topic '#{topic}'")

    # Pozovi handler funkciju za procesiranje poruke
    try do
      state.handler.(topic, message)
    rescue
      error ->
        Logger.error("Error processing message in subscriber '#{state.name}': #{inspect(error)}")
    end

    new_state = %{state | messages_received: state.messages_received + 1}
    {:noreply, new_state}
  end

  defp register_topic(topic) do
    Registry.register(@registry, topic, [])
  end

  defp unregister_topic(topic) do
    Registry.unregister(@registry, topic)
  end

  defp generate_name do
    "subscriber_#{:erlang.unique_integer([:positive])}"
  end

  defp default_handler(topic, message) do
    IO.puts("[#{topic}] Received: #{inspect(message)}")
  end
end
