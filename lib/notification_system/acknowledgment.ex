defmodule NotificationSystem.Acknowledgment do
  @moduledoc """
  Mehanizam za potvrdu poruka i ponovno slanje.

  Pruža:
  - Dostavljanje bar jednom
  - Podesive intervale ponovnog slanja
  - Eksponencijalno povecanje intervala
  - Automatsko ponovno slanje nepotvrdjenih poruka
  """
  use GenServer
  require Logger

  alias NotificationSystem.{Persistence, DeadLetterQueue}

  @retry_interval 5_000
  @max_retries 3
  @backoff_multiplier 2

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Potvrdjuje uspesnu isporuku poruke
  """
  def ack(message_id) do
    GenServer.cast(__MODULE__, {:ack, message_id})
  end

  @doc """
  Neuspesno poslata poruka -> postavlja je u red za retry
  """
  def nack(message_id, reason \\ :processing_failed) do
    GenServer.cast(__MODULE__, {:nack, message_id, reason})
  end

  @doc """
  Dobija pending potvrdu
  """
  def pending_acks do
    GenServer.call(__MODULE__, :pending_acks)
  end

  @doc """
  Gets acknowledgment statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_retry_check()

    state = %{
      pending: %{},  # message_id => %{sent_at, attempts, next_retry}
      ack_count: 0,
      nack_count: 0
    }

    Logger.info("Acknowledgment system started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:ack, message_id}, state) do
    case Map.get(state.pending, message_id) do
      nil ->
        Logger.warn("Received ACK for unknown message: #{message_id}")
        {:noreply, state}

      _info ->
        # Oznacava kao isporuceno
        Persistence.mark_delivered(message_id)

        new_state = %{
          state |
          pending: Map.delete(state.pending, message_id),
          ack_count: state.ack_count + 1
        }

        Logger.debug("Message #{message_id} acknowledged")
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:nack, message_id, reason}, state) do
    case Map.get(state.pending, message_id) do
      nil ->
        Logger.warn("Received NACK for unknown message: #{message_id}")
        {:noreply, state}

      info ->
        attempts = info.attempts + 1

        if attempts >= @max_retries do
          # Dodaje u dead letter red
          DeadLetterQueue.add(message_id, reason)

          new_state = %{
            state |
            pending: Map.delete(state.pending, message_id),
            nack_count: state.nack_count + 1
          }

          Logger.warn("Message #{message_id} exceeded max retries, moved to DLQ")
          {:noreply, new_state}
        else
          # Zakazuje ponovni pokusaj sa exponential backoff
          backoff = @retry_interval * :math.pow(@backoff_multiplier, attempts - 1) |> round()
          next_retry = DateTime.add(DateTime.utc_now(), backoff, :millisecond)

          updated_info = %{info | attempts: attempts, next_retry: next_retry}
          new_state = %{
            state |
            pending: Map.put(state.pending, message_id, updated_info),
            nack_count: state.nack_count + 1
          }

          Logger.debug("Message #{message_id} NACK'd, retry #{attempts}/#{@max_retries} scheduled")
          {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_call(:pending_acks, _from, state) do
    {:reply, Map.keys(state.pending), state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      pending_count: map_size(state.pending),
      ack_count: state.ack_count,
      nack_count: state.nack_count,
      success_rate: calculate_success_rate(state.ack_count, state.nack_count)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:retry_check, state) do
    now = DateTime.utc_now()

    # Pronalazi poruke koje zahtevaju retry
    to_retry = Enum.filter(state.pending, fn {_id, info} ->
      DateTime.compare(now, info.next_retry) in [:gt, :eq]
    end)

    # Retry poruka
    Enum.each(to_retry, fn {message_id, info} ->
      retry_message(message_id, info)
    end)

    schedule_retry_check()
    {:noreply, state}
  end

  @impl true
  def handle_info({:track_message, message_id, topic, message}, state) do
    info = %{
      topic: topic,
      message: message,
      sent_at: DateTime.utc_now(),
      attempts: 0,
      next_retry: DateTime.add(DateTime.utc_now(), @retry_interval, :millisecond)
    }

    new_state = %{state | pending: Map.put(state.pending, message_id, info)}
    {:noreply, new_state}
  end

  # Helper za pronalaz poruke
  def track_message(message_id, topic, message) do
    send(__MODULE__, {:track_message, message_id, topic, message})
  end

  # Private functions

  defp retry_message(message_id, info) do
    Logger.info("Retrying message #{message_id}, attempt #{info.attempts + 1}")

    # Re-publish poruke
    NotificationSystem.Broker.publish(info.topic, info.message)

    # Update persistence
    Persistence.mark_failed(message_id)
  end

  defp calculate_success_rate(acks, nacks) do
    total = acks + nacks
    if total > 0, do: Float.round(acks / total * 100, 2), else: 0.0
  end

  defp schedule_retry_check do
    Process.send_after(self(), :retry_check, @retry_interval)
  end
end
