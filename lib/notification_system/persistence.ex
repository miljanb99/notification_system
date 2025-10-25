defmodule NotificationSystem.Persistence do
  @moduledoc """
  Sloj za perzistenciju poruka koristeci Mnesia distribuiranu bazu podataka.

  Funkcionalnosti:
  - Trajno skladistenje poruka
  - Mogucnost ponovnog izvrsavanja poruka
  - Distribuirana replikacija između nodova
  - Transaction support
  """
  require Logger

  @table_name :messages
  @retention_hours 24

  @doc """
  Inicijalizacija Mnesia baze podataka i kreiranje potrebnih tabela
  """
  def init do
    # Create schema if it doesn't exist
    case :mnesia.create_schema([node()]) do
      :ok ->
        Logger.info("Mnesia schema created")
      {:error, {_, {:already_exists, _}}} ->
        Logger.info("Mnesia schema already exists")
      error ->
        Logger.error("Failed to create schema: #{inspect(error)}")
    end

    # Startovanje
    :mnesia.start()

    # Messages tabela (ram_copies za unnamed nodes, disc_copies za named nodes)
    table_opts = if node() == :nonode@nohost do
      [
        attributes: [:id, :topic, :message, :timestamp, :status, :attempts, :priority],
        ram_copies: [node()],
        type: :set,
        index: [:topic, :status, :timestamp]
      ]
    else
      [
        attributes: [:id, :topic, :message, :timestamp, :status, :attempts, :priority],
        disc_copies: [node()],
        type: :set,
        index: [:topic, :status, :timestamp]
      ]
    end

    case :mnesia.create_table(@table_name, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Messages table created")
      {:aborted, {:already_exists, _}} ->
        Logger.info("Messages table already exists")
      error ->
        Logger.error("Failed to create table: #{inspect(error)}")
    end

    # Sacekaj da tabele budu spremne
    :mnesia.wait_for_tables([@table_name], 5000)

    :ok
  end

  @doc """
  Cuva poruke sa svim meta-podacima
  """
  def store_message(topic, message, opts \\ []) do
    priority = Keyword.get(opts, :priority, 5)
    id = generate_id()

    record = {
      @table_name,
      id,
      topic,
      message,
      DateTime.utc_now(),
      :pending,
      0,
      priority
    }

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        {:ok, id}
      {:aborted, reason} ->
        Logger.error("Failed to store message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Belezi poruku kao isporucenu
  """
  def mark_delivered(message_id) do
    update_status(message_id, :delivered)
  end

  @doc """
  Belezi poruku kao failed i povecava attempt counter
  """
  def mark_failed(message_id) do
    transaction = fn ->
      case :mnesia.read(@table_name, message_id) do
        [{@table_name, id, topic, msg, ts, _status, attempts, priority}] ->
          updated = {@table_name, id, topic, msg, ts, :failed, attempts + 1, priority}
          :mnesia.write(updated)
        [] ->
          {:error, :not_found}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} -> :ok
      {:atomic, {:error, reason}} -> {:error, reason}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Dohvata poruke koje cekaju na povovno izvrsavanje
  """
  def get_pending_messages(max_attempts \\ 3) do
    transaction = fn ->
      :mnesia.match_object({@table_name, :_, :_, :_, :_, :pending, :_, :_})
      |> Enum.filter(fn {_, _, _, _, _, _, attempts, _} -> attempts < max_attempts end)
      |> Enum.sort_by(fn {_, _, _, _, _, _, _, priority} -> -priority end)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, messages} ->
        Enum.map(messages, &format_message/1)
      {:aborted, reason} ->
        Logger.error("Failed to get pending messages: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Dohvata failed poruke za dlq
  """
  def get_failed_messages do
    transaction = fn ->
      :mnesia.match_object({@table_name, :_, :_, :_, :_, :failed, :_, :_})
    end

    case :mnesia.transaction(transaction) do
      {:atomic, messages} -> Enum.map(messages, &format_message/1)
      {:aborted, _} -> []
    end
  end

  @doc """
  Dohvata poruke po topic-u za ponovno slanje
  """
  def get_messages_by_topic(topic, limit \\ 100) do
    transaction = fn ->
      :mnesia.index_read(@table_name, topic, :topic)
      |> Enum.take(limit)
      |> Enum.sort_by(fn {_, _, _, _, timestamp, _, _, _} -> timestamp end, {:desc, DateTime})
    end

    case :mnesia.transaction(transaction) do
      {:atomic, messages} -> Enum.map(messages, &format_message/1)
      {:aborted, _} -> []
    end
  end

  @doc """
  Cisti stare poruke nakon odredjenog perioda cuvanja
  """
  def cleanup_old_messages do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_hours * 3600, :second)

    transaction = fn ->
      :mnesia.foldl(
        fn {_, id, _, _, timestamp, _, _, _} = record, acc ->
          if DateTime.compare(timestamp, cutoff) == :lt do
            :mnesia.delete({@table_name, id})
            acc + 1
          else
            acc
          end
        end,
        0,
        @table_name
      )
    end

    case :mnesia.transaction(transaction) do
      {:atomic, count} ->
        Logger.info("Cleaned up #{count} old messages")
        {:ok, count}
      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Dohvatanje statistika za sacuvane poruke
  """
  def stats do
    transaction = fn ->
      total = :mnesia.table_info(@table_name, :size)

      pending = length(:mnesia.match_object({@table_name, :_, :_, :_, :_, :pending, :_, :_}))
      delivered = length(:mnesia.match_object({@table_name, :_, :_, :_, :_, :delivered, :_, :_}))
      failed = length(:mnesia.match_object({@table_name, :_, :_, :_, :_, :failed, :_, :_}))

      %{
        total: total,
        pending: pending,
        delivered: delivered,
        failed: failed
      }
    end

    case :mnesia.transaction(transaction) do
      {:atomic, stats} -> stats
      {:aborted, _} -> %{total: 0, pending: 0, delivered: 0, failed: 0}
    end
  end

  # Private functions

  defp update_status(message_id, new_status) do
    transaction = fn ->
      case :mnesia.read(@table_name, message_id) do
        [{@table_name, id, topic, msg, ts, _status, attempts, priority}] ->
          updated = {@table_name, id, topic, msg, ts, new_status, attempts, priority}
          :mnesia.write(updated)
        [] ->
          {:error, :not_found}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} -> :ok
      {:atomic, {:error, reason}} -> {:error, reason}
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp format_message({@table_name, id, topic, message, timestamp, status, attempts, priority}) do
    %{
      id: id,
      topic: topic,
      message: message,
      timestamp: timestamp,
      status: status,
      attempts: attempts,
      priority: priority
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
