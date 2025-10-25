defmodule NotificationSystem.Router do
  @moduledoc """
  Napredno rutiranje poruka sa filterima baziranim na sadrzaju i rukovanjem prioritetima.

  Funkcionalnosti:
  - Rutiranje bazirano na sadrzaju
  - Upravljanje redom prioriteta
  - Pravila za filtriranje poruka
  - Conditional delivery
  - Custom routing logic
  """
  use GenServer
  require Logger

  @registry NotificationSystem.Registry

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Dodaje routing pravilo na osnovu sadrzaja

  ## Na primer:

      # Route iskljucivo urgent poruke
      Router.add_rule("alerts", fn msg ->
        Map.get(msg, :priority) == :urgent
      end)

      # Route zasnovane na user id-u
      Router.add_rule("user_notifications", fn msg ->
        Map.get(msg, :user_id) in [1, 2, 3]
      end)
  """
  def add_rule(topic, filter_fn) when is_function(filter_fn, 1) do
    GenServer.call(__MODULE__, {:add_rule, topic, filter_fn})
  end

  @doc """
  Brisanje routing pravila
  """
  def remove_rule(rule_id) do
    GenServer.call(__MODULE__, {:remove_rule, rule_id})
  end

  @doc """
  Routes poruke sa prioritetom i filter opcijom
  """
  def route_message(topic, message, opts \\ []) do
    priority = Keyword.get(opts, :priority, 5)
    GenServer.cast(__MODULE__, {:route, topic, message, priority})
  end

  @doc """
  Dohvatanje routing statistike
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Izlistava sva aktiva routing pravila
  """
  def list_rules do
    GenServer.call(__MODULE__, :list_rules)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      rules: %{},          # rule_id => %{topic, filter_fn}
      priority_queues: %{}, # priority (1-10) => [messages]
      routed_count: 0,
      filtered_count: 0,
      next_rule_id: 1
    }

    # Startuje priority queue procesor
    schedule_queue_processing()

    Logger.info("Router started with priority queue processing")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_rule, topic, filter_fn}, _from, state) do
    rule_id = state.next_rule_id
    rule = %{topic: topic, filter: filter_fn}

    new_rules = Map.put(state.rules, rule_id, rule)
    new_state = %{state | rules: new_rules, next_rule_id: rule_id + 1}

    Logger.info("Added routing rule #{rule_id} for topic: #{topic}")
    {:reply, {:ok, rule_id}, new_state}
  end

  @impl true
  def handle_call({:remove_rule, rule_id}, _from, state) do
    new_rules = Map.delete(state.rules, rule_id)
    {:reply, :ok, %{state | rules: new_rules}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    queue_stats = Enum.map(state.priority_queues, fn {priority, messages} ->
      {priority, length(messages)}
    end) |> Enum.into(%{})

    stats = %{
      routed_count: state.routed_count,
      filtered_count: state.filtered_count,
      active_rules: map_size(state.rules),
      queue_sizes: queue_stats,
      total_queued: queue_stats |> Map.values() |> Enum.sum()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_rules, _from, state) do
    rules = Enum.map(state.rules, fn {id, rule} ->
      %{id: id, topic: rule.topic}
    end)

    {:reply, rules, state}
  end

  @impl true
  def handle_cast({:route, topic, message, priority}, state) do
    # Primenjuje filtering pravila
    matching_rules = find_matching_rules(state.rules, topic, message)

    if matching_rules == [] and map_size(state.rules) > 0 do
      # Filtered out poruka
      Logger.debug("Message filtered out for topic: #{topic}")
      {:noreply, %{state | filtered_count: state.filtered_count + 1}}
    else
      # Dodaje u priority queue
      queue_item = %{
        topic: topic,
        message: message,
        timestamp: System.monotonic_time(:microsecond),
        rules: matching_rules
      }

      priority_queues = Map.update(
        state.priority_queues,
        priority,
        [queue_item],
        fn queue -> [queue_item | queue] end
      )

      {:noreply, %{state | priority_queues: priority_queues}}
    end
  end

  @impl true
  def handle_info(:process_queues, state) do
    # Obrada poruka od najviseg do najnizeg prioriteta
    priorities = Map.keys(state.priority_queues) |> Enum.sort(:desc)

    {new_queues, processed_count} = Enum.reduce(priorities, {state.priority_queues, 0}, fn priority, {queues, count} ->
      case Map.get(queues, priority) do
        nil ->
          {queues, count}

        [] ->
          {Map.delete(queues, priority), count}

        messages ->
          # Batch poruka (10 po cycle)
          {to_process, remaining} = Enum.split(messages, 10)

          Enum.each(to_process, fn item ->
            deliver_message(item.topic, item.message)
          end)

          new_queues = if remaining == [] do
            Map.delete(queues, priority)
          else
            Map.put(queues, priority, remaining)
          end

          {new_queues, count + length(to_process)}
      end
    end)

    schedule_queue_processing()

    {:noreply, %{
      state |
      priority_queues: new_queues,
      routed_count: state.routed_count + processed_count
    }}
  end

  # Private functions

  defp find_matching_rules(rules, topic, message) do
    rules
    |> Enum.filter(fn {_id, rule} ->
      rule.topic == topic and apply_filter(rule.filter, message)
    end)
    |> Enum.map(fn {id, _rule} -> id end)
  end

  defp apply_filter(filter_fn, message) do
    try do
      filter_fn.(message)
    rescue
      error ->
        Logger.error("Filter function error: #{inspect(error)}")
        false
    end
  end

  defp deliver_message(topic, message) do
    # Pronalazi subs za topic
    subscribers = Registry.lookup(@registry, topic)

    # Slanje svakom subs
    Enum.each(subscribers, fn {pid, _value} ->
      send(pid, {:notification, topic, message})
    end)
  end

  defp schedule_queue_processing do
    Process.send_after(self(), :process_queues, 100)
  end
end
