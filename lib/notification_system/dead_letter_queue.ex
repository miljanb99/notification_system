defmodule NotificationSystem.DeadLetterQueue do
  @moduledoc """
  Red za nedostavljene poruke (Dead Letter Queue) za rukovanje porukama koje nisu uspele da budu dostavljene.

  Funkcionalnosti:
  - Automatsko cuvanje neuspelih poruka
  - Mogucnost rucnog ponovnog slanja
  - Analiza uzoraka grsšaka
  - Configurable retention policies
  """
  use GenServer
  require Logger

  alias NotificationSystem.Persistence

  @check_interval 60_000  # Provera svakog minuta
  @max_attempts 3

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Dodaje poruku u dead-letter queue
  """
  def add(message_id, reason) do
    GenServer.cast(__MODULE__, {:add, message_id, reason})
  end

  @doc """
  Dohvata sve poruke iz dlq
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Retry specific (message_id) poruke
  """
  def retry(message_id) do
    GenServer.call(__MODULE__, {:retry, message_id})
  end

  @doc """
  Retry svih poruka iz dlq
  """
  def retry_all do
    GenServer.call(__MODULE__, :retry_all)
  end

  @doc """
  Dohvatanje statistike o dlq
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_check()

    state = %{
      failed_count: 0,
      retry_count: 0,
      last_check: DateTime.utc_now()
    }

    Logger.info("Dead letter queue started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:add, message_id, reason}, state) do
    Logger.warning("Message #{message_id} added to DLQ: #{inspect(reason)}")
    Persistence.mark_failed(message_id)

    new_state = %{state | failed_count: state.failed_count + 1}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    messages = Persistence.get_failed_messages()
    {:reply, messages, state}
  end

  @impl true
  def handle_call({:retry, message_id}, _from, state) do
    result = retry_message(message_id)
    new_state = if match?({:ok, _}, result),
      do: %{state | retry_count: state.retry_count + 1},
      else: state

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:retry_all, _from, state) do
    messages = Persistence.get_failed_messages()
    results = Enum.map(messages, fn msg -> retry_message(msg.id) end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    new_state = %{state | retry_count: state.retry_count + successful}

    {:reply, {:ok, successful}, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    failed_messages = Persistence.get_failed_messages()

    stats = %{
      total_failed: length(failed_messages),
      failed_count: state.failed_count,
      retry_count: state.retry_count,
      last_check: state.last_check,
      failure_by_topic: analyze_failures(failed_messages)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:check_failed, state) do
    # Periodicna provera poruka koje bi trebale da budu premestene u dlq
    pending = Persistence.get_pending_messages(@max_attempts)

    over_limit = Enum.filter(pending, fn msg -> msg.attempts >= @max_attempts end)

    Enum.each(over_limit, fn msg ->
      add(msg.id, :max_attempts_exceeded)
    end)

    schedule_check()
    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  # Private functions

  defp retry_message(message_id) do
    case Persistence.get_pending_messages() |> Enum.find(fn m -> m.id == message_id end) do
      nil ->
        {:error, :not_found}

      message ->
        # Resetuj status poruke u pending i odradi republish
        :mnesia.transaction(fn ->
          case :mnesia.read(:messages, message_id) do
            [{:messages, id, topic, msg, ts, _status, _attempts, priority}] ->
              updated = {:messages, id, topic, msg, ts, :pending, 0, priority}
              :mnesia.write(updated)
            [] ->
              {:error, :not_found}
          end
        end)

        # Republishuj poruku
        NotificationSystem.Broker.publish(message.topic, message.message)
        Logger.info("Retried message #{message_id}")
        {:ok, message_id}
    end
  end

  defp analyze_failures(messages) do
    messages
    |> Enum.group_by(fn msg -> msg.topic end)
    |> Enum.map(fn {topic, msgs} -> {topic, length(msgs)} end)
    |> Enum.into(%{})
  end

  defp schedule_check do
    Process.send_after(self(), :check_failed, @check_interval)
  end
end
