defmodule NotificationSystem.Publisher do
  @moduledoc """
  Publisher modul pruza jednostavan API za slanje poruka.

  Publisher nije GenServer već stateless modul jer ne cuva stanje.
  Samo prosleđuje poruke brokeru.
  """
  require Logger

  @doc """
  Objavljuje poruku na odredjenu temu (topic).

  ## Options

  - `:persist` - Cuvanje poruke u persistence sloju (default: false)
  - `:priority` - Prioritet poruke 1-10 (default: 5)
  - `:use_router` - Koristi advance rutiranje sa filtering opcijom (default: false)
  - `:encrypt` -  Sifruj poruku pre slanja (default: false)
  - `:key` -  Enkripcioni kljuc (potreban if encrypt: true)

  ## Primeri

      iex> NotificationSystem.Publisher.publish("user.login", %{user_id: 123})
      :ok

      iex> NotificationSystem.Publisher.publish("order.created", %{order_id: 456, total: 99.99}, persist: true, priority: 8)
      :ok
  """
  def publish(topic, message, opts \\ []) when is_binary(topic) do
    Logger.debug("Publishing to topic '#{topic}': #{inspect(message)}")

    # Hendluj enkripciju ukoliko je potrebna
    final_message = if Keyword.get(opts, :encrypt, false) do
      key = Keyword.get(opts, :key)
      if key do
        case NotificationSystem.Encryption.secure_encrypt(message, key) do
          {:ok, encrypted} -> encrypted
          {:error, _} -> message  # Fall back to unencrypted
        end
      else
        Logger.warn("Encryption requested but no key provided")
        message
      end
    else
      message
    end

    NotificationSystem.Broker.publish(topic, final_message, opts)
    :ok
  end

  @doc """
  Objavljuje poruku na sve subscribere (broadcast).

  ## Primeri

      iex> NotificationSystem.Publisher.broadcast(%{type: "system_maintenance", message: "Server restart at 3am"})
      :ok
  """
  def broadcast(message) do
    Logger.debug("Broadcasting message: #{inspect(message)}")
    NotificationSystem.Broker.broadcast(message)
    :ok
  end

  @doc """
  Sinhronizovano objavljuje poruku i vraca broj subscribera koji su je primili.
  """
  def publish_sync(topic, message) do
    # Brojac subscribera pre slanja
    subscribers_before = count_subscribers(topic)

    publish(topic, message)

    # Pauziraj kratko da bi poruke stigle
    Process.sleep(10)

    {:ok, subscribers_before}
  end

  @doc """
  Vraca broj aktivnih subscribera za datu temu
  """
  def count_subscribers(topic) do
    Registry.lookup(NotificationSystem.Registry, topic)
    |> length()
  end

  @doc """
  Vraca sve aktivne teme u sistemu
  """
  def list_topics do
    Registry.select(NotificationSystem.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
  end
end
