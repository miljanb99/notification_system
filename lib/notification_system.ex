defmodule NotificationSystem do
  @moduledoc """
  Distribuirani sistem za notifikacije implementiran u Elixir-u koriscenjem OTP modela.

  Ovaj sistem implementira publish/subscribe pattern sa sledecim karakteristikama:
  - Konkurentnost kroz actor model (GenServer procesi)
  - Otpornost na greske (Supervisor, fault tolerance)
  - Skalabilnost (distribuirani nodovi)
  - Topic-based routing

  ## Arhitektura

  - **Broker**: Centralni GenServer za distribuciju poruka
  - **Publisher**: Klijentski API za slanje poruka
  - **Subscriber**: GenServer procesi koji primaju poruke
  - **Registry**: Efikasno pracenje subscribera
  - **Supervisor**: Upravljanje zivotnim ciklusom i restart logika

  ## Primeri koriscenja

      # Kreiranje subscribera
      NotificationSystem.subscribe("notifications", ["user.login", "user.logout"])

      # Slanje poruke
      NotificationSystem.publish("user.login", %{user_id: 123, timestamp: DateTime.utc_now()})

      # Statistika
      NotificationSystem.stats()
  """

  alias NotificationSystem.{Publisher, SubscriberManager, Broker, Monitor, ClusterManager}

  # Publisher API

  @doc """
  Objavljuje poruku na određenu temu.

  ## Opcije
  - `:persist` - Cuva u sloju perzistencije
  - `:priority` - Prioritet poruke (1-10)
  - `:use_router` - Koristi napredno rutiranje sa filterima
  - `:encrypt` - Enkriptuj poruku
  - `:key` - Kljuc za enkripciju
  """
  defdelegate publish(topic, message, opts \\ []), to: Publisher

  @doc """
  Broadcast poruka svim subscriberima.
  """
  defdelegate broadcast(message), to: Publisher

  @doc """
  Vraca broj subscribera za određenu temu.
  """
  defdelegate count_subscribers(topic), to: Publisher

  @doc """
  Lista svih aktivnih tema.
  """
  defdelegate list_topics(), to: Publisher

  # Subscriber API

  @doc """
  Kreira novog subscribera.

  ## Primeri

      # Jednostavan subscriber
      NotificationSystem.subscribe("my_subscriber", ["orders", "payments"])

      # Subscriber sa custom handler funkcijom
      NotificationSystem.subscribe("logger", ["errors"], fn topic, msg ->
        IO.puts("[ERROR] \#{topic}: \#{inspect(msg)}")
      end)
  """
  def subscribe(name, topics, handler \\ nil) when is_list(topics) do
    opts = [name: name, topics: topics]
    opts = if handler, do: Keyword.put(opts, :handler, handler), else: opts

    SubscriberManager.create_subscriber(opts)
  end

  @doc """
  Prekida subscriber-a
  """
  defdelegate unsubscribe(pid), to: SubscriberManager, as: :stop_subscriber

  @doc """
  Lista svih subscriber-a
  """
  defdelegate list_subscribers(), to: SubscriberManager

  # Monitoring API

  @doc """
  Vraca statistiku brokera
  """
  defdelegate broker_stats(), to: Broker, as: :stats

  @doc """
  Vraca kompletan pregled sistema
  """
  defdelegate system_stats(), to: Monitor

  @doc """
  Kombinovana statistika
  """
  def stats do
    %{
      broker: broker_stats(),
      total_subscribers: SubscriberManager.count_subscribers(),
      topics: list_topics(),
      nodes: ClusterManager.list_nodes(),
      metrics: NotificationSystem.Metrics.get_metrics(),
      rate_limiter: NotificationSystem.RateLimiter.stats(),
      persistence: NotificationSystem.Persistence.stats(),
      dead_letter_queue: NotificationSystem.DeadLetterQueue.stats(),
      acknowledgments: NotificationSystem.Acknowledgment.stats()
    }
  end


  @doc """
  Dohvata detaljne metrike performansi
  """
  defdelegate metrics(), to: NotificationSystem.Metrics, as: :get_metrics

  @doc """
  Dohvata metrike u Prometheus formatu
  """
  defdelegate prometheus_metrics(), to: NotificationSystem.Metrics, as: :prometheus_format

  @doc """
  Konfigurise rate_limit za temu
  """
  defdelegate configure_rate_limit(topic, rate, burst), to: NotificationSystem.RateLimiter, as: :configure_topic

  @doc """
  Dodaje content-based routing rule
  """
  defdelegate add_routing_rule(topic, filter_fn), to: NotificationSystem.Router, as: :add_rule

  @doc """
  Izlistava sve poruke iz dlq
  """
  defdelegate dead_letters(), to: NotificationSystem.DeadLetterQueue, as: :list

  @doc """
  Ponovo pokusava slanje neuspesnih poruke iz dlq
  """
  defdelegate retry_message(message_id), to: NotificationSystem.DeadLetterQueue, as: :retry

  @doc """
  Dohvata sacuvane poruke po topic-u
  """
  defdelegate get_messages(topic, limit \\ 100), to: NotificationSystem.Persistence, as: :get_messages_by_topic

  @doc """
  Pokrece sveobuhvatne benchmark testove performansi
  """
  defdelegate benchmark(opts \\ []), to: NotificationSystem.Benchmark, as: :run_suite

  @doc """
  Generise kljuc za enkripciju za slanje poruka
  """
  defdelegate generate_key(), to: NotificationSystem.Encryption

  @doc """
  Enkriptuje poruku sa datim kljucem
  """
  defdelegate encrypt_message(message, key), to: NotificationSystem.Encryption, as: :secure_encrypt

  @doc """
  Dekriptuje poruku sa datim kljucem
  """
  defdelegate decrypt_message(encrypted, key), to: NotificationSystem.Encryption, as: :secure_decrypt

  # Cluster API

  @doc """
  Povezuje se sa drugim nodom
  """
  defdelegate connect_node(node), to: ClusterManager

  @doc """
  Lista nodova u klasteru
  """
  defdelegate cluster_nodes(), to: ClusterManager, as: :list_nodes

  @doc """
  Globalno slanje poruke na sve nodove
  """
  defdelegate global_publish(topic, message), to: ClusterManager

  @doc """
  Statistika sa svih nodova
  """
  defdelegate cluster_stats(), to: ClusterManager, as: :global_stats

  # Utility Functions

  @doc """
  Demo funkcija koja demonstrira sistem.
  """
  def demo do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("NotificationSystem Enhanced Demo")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # 1. Kreiraj subscribere
    IO.puts("Creating subscribers...")
    {:ok, _} = subscribe("email_service", ["user.registered", "user.login"])
    {:ok, _} = subscribe("analytics", ["user.registered", "user.login", "order.created"])
    {:ok, _} = subscribe("logger", ["user.login"], fn topic, msg ->
      IO.puts("  [LOG] #{topic}: #{inspect(msg)}")
    end)

    Process.sleep(200)

    # 2. Basic publishing
    IO.puts("\n2️⃣  Publishing basic messages...")
    publish("user.registered", %{user_id: 1, email: "user@example.com"})
    publish("user.login", %{user_id: 1, ip: "192.168.1.1"})

    # 3. Persistent messages
    IO.puts("\n3️⃣  Publishing with persistence...")
    publish("order.created", %{order_id: 100, total: 299.99}, persist: true, priority: 8)

    # 4. Encryption demo
    IO.puts("\n4️⃣  Demonstrating encryption...")
    key = generate_key()
    {:ok, encrypted} = encrypt_message(%{secret: "confidential data"}, key)
    IO.puts("Message encrypted: #{String.slice(encrypted.ciphertext, 0, 20)}...")
    {:ok, decrypted} = decrypt_message(encrypted, key)
    IO.puts("Message decrypted: #{inspect(decrypted)}")

    # 5. Rate limiting demo
    IO.puts("\n5️⃣  Demonstrating rate limiting...")
    configure_rate_limit("limited_topic", 5, 10)  # 5 msg/s, burst 10
    IO.puts("  ✓ Rate limit configured for 'limited_topic'")

    # 6. Content-based routing
    IO.puts("\nDemonstrating content-based routing...")
    {:ok, rule_id} = add_routing_rule("urgent_orders", fn msg ->
      Map.get(msg, :priority) == :urgent
    end)
    IO.puts("Routing rule #{rule_id} added")

    Process.sleep(500)

    # 7. Show comprehensive stats
    IO.puts("\nSystem Statistics:")
    stats = stats()
    IO.puts("Messages sent: #{stats.broker.messages_sent}")
    IO.puts("Total subscribers: #{stats.total_subscribers}")
    IO.puts("Topics: #{length(stats.topics)}")
    IO.puts("Persisted messages: #{stats.persistence.total}")
    IO.puts("Throughput: #{stats.metrics.throughput_per_second} msg/s")
    IO.puts("Avg latency: #{Float.round(stats.metrics.latency_ms.avg, 2)} ms")

    # 8. Metrics in Prometheus format
    IO.puts("\n8️⃣  Prometheus Metrics Sample:")
    prometheus = prometheus_metrics()
    IO.puts(String.slice(prometheus, 0, 300) <> "...")

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Demo Complete! Try these commands:")
    IO.puts("NotificationSystem.metrics()         - Detailed metrics")
    IO.puts("NotificationSystem.benchmark()       - Performance benchmarks")
    IO.puts("NotificationSystem.dead_letters()    - View failed messages")
    IO.puts("NotificationSystem.get_messages(\"topic\") - Get persisted messages")
    IO.puts(String.duplicate("=", 70) <> "\n")
  end

  @doc """
  Advanced demo koja prikazuje sve advanced funkcionalnost projekta.
  """
  def advanced_demo do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("NotificationSystem Advanced Features Demo")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # Priority messaging
    IO.puts("Priority Queue Demo:")
    subscribe("priority_test", ["orders"])
    publish("orders", %{type: "regular"}, priority: 5)
    publish("orders", %{type: "urgent"}, priority: 10)
    publish("orders", %{type: "low"}, priority: 1)
    IO.puts("  ✓ Messages with different priorities sent")

    Process.sleep(200)

    # Content filtering
    IO.puts("\nContent-Based Filtering:")
    add_routing_rule("premium_users", fn msg ->
      Map.get(msg, :user_tier) == :premium
    end)
    subscribe("premium_handler", ["premium_users"])
    publish("premium_users", %{user_tier: :premium, user_id: 1}, use_router: true)
    publish("premium_users", %{user_tier: :basic, user_id: 2}, use_router: true)
    IO.puts("  ✓ Only premium user message should be delivered")

    Process.sleep(200)

    # Dead letter queue
    IO.puts("\nDead Letter Queue:")
    IO.puts("DLQ stats: #{inspect(NotificationSystem.DeadLetterQueue.stats())}")

    # Persistence query
    IO.puts("\nMessage Persistence:")
    publish("archived_topic", %{data: "test"}, persist: true)
    Process.sleep(100)
    messages = get_messages("archived_topic", 10)
    IO.puts("Retrieved #{length(messages)} persisted messages")

    IO.puts("\n" <> String.duplicate("=", 70) <> "\n")
  end

  @doc """
  Stress test - dosta subs sa dosta poruka
  """
  def stress_test(subscriber_count \\ 100, message_count \\ 1000) do
    IO.puts("\n=== Stress Test ===")
    IO.puts("Kreiranje #{subscriber_count} subscribera...")

    start_time = System.monotonic_time(:millisecond)

    # Kreiraj subscribere
    SubscriberManager.create_multiple_subscribers(
      subscriber_count,
      [topics: ["stress.test"]]
    )

    subscriber_creation_time = System.monotonic_time(:millisecond) - start_time
    IO.puts("Subscriberi kreirani za: #{subscriber_creation_time}ms")

    # Salji poruke
    IO.puts("Sending #{message_count} messages...")
    message_start = System.monotonic_time(:millisecond)

    1..message_count
    |> Enum.each(fn i ->
      publish("stress.test", %{index: i, timestamp: DateTime.utc_now()})
    end)

    message_send_time = System.monotonic_time(:millisecond) - message_start

    Process.sleep(1000)  # Sačekaj da se poruke dostave

    total_time = System.monotonic_time(:millisecond) - start_time

    stats = broker_stats()

    IO.puts("\n=== Rezultati ===")
    IO.puts("Vreme kreiranja subscribera: #{subscriber_creation_time}ms")
    IO.puts("Vreme slanja poruka: #{message_send_time}ms")
    IO.puts("Ukupno vreme: #{total_time}ms")
    IO.puts("Poruka poslatih: #{stats.messages_sent}")
    IO.puts("Throughput: #{round(message_count / (message_send_time / 1000))} msg/s")
    IO.puts("==================\n")
  end

end
