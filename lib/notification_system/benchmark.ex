defmodule NotificationSystem.Benchmark do
  @moduledoc """
  Paket za benchmark testove i analizu performansi.

  Funkcionalnosti:
  - Benchmark protoka poruka
  - Merenje kasnjenja
  - Testiranje skalabilnosti
  - Uporedna analiza
  - Generisanje izvestaja
  """
  require Logger

  alias NotificationSystem.{SubscriberManager, Metrics}

  @doc """
  Pokrece kompletan benchmark.
  """
  def run_suite(opts \\ []) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("NotificationSystem performance Benchmark suite")
    IO.puts(String.duplicate("=", 70) <> "\n")

    results = %{
      throughput: benchmark_throughput(opts),
      latency: benchmark_latency(opts),
      scalability: benchmark_scalability(opts),
      concurrent_publishers: benchmark_concurrent_publishers(opts),
      system_info: collect_system_info()
    }

    print_report(results)
    results
  end

  @doc """
  Meri propusnost poruka (poruke u sekundi).
  """
  def benchmark_throughput(opts \\ []) do
    message_count = Keyword.get(opts, :messages, 10_000)
    subscriber_count = Keyword.get(opts, :subscribers, 100)

    IO.puts("Throughput Benchmark")
    IO.puts("Messages: #{message_count}, subscribers: #{subscriber_count}")

    # Setup
    SubscriberManager.create_multiple_subscribers(
      subscriber_count,
      [topics: ["bench.throughput"]]
    )

    Process.sleep(500)  # Inicijalizacija subscribers

    # Benchmark
    start_time = System.monotonic_time(:millisecond)

    1..message_count
    |> Enum.each(fn i ->
      NotificationSystem.publish("bench.throughput", %{
        index: i,
        timestamp: System.monotonic_time(:microsecond)
      })
    end)

    end_time = System.monotonic_time(:millisecond)
    elapsed_ms = end_time - start_time

    # Cekanje na isporuku poruke
    Process.sleep(2000)

    throughput = (message_count / elapsed_ms) * 1000

    result = %{
      messages: message_count,
      subscribers: subscriber_count,
      elapsed_ms: elapsed_ms,
      throughput_per_sec: Float.round(throughput, 2),
      msg_per_subscriber_per_sec: Float.round(throughput / subscriber_count, 2)
    }

    IO.puts("Throughput: #{result.throughput_per_sec} msg/s")
    IO.puts("Per subscriber: #{result.msg_per_subscriber_per_sec} msg/s\n")

    result
  end

  @doc """
  Meri latency end-to-end message.
  """
  def benchmark_latency(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1_000)

    IO.puts("Latency Benchmark")
    IO.puts("Iterations: #{iterations}")

    # Kreiranje jednog sub koji meri latency
    test_pid = self()

    handler = fn _topic, msg ->
      receive_time = System.monotonic_time(:microsecond)
      send_time = Map.get(msg, :send_time)
      latency = receive_time - send_time
      send(test_pid, {:latency, latency})
    end

    {:ok, _} = NotificationSystem.subscribe("bench_latency", ["bench.latency"], handler)

    Process.sleep(100)

    # Merenje latencies
    latencies = Enum.map(1..iterations, fn _i ->
      send_time = System.monotonic_time(:microsecond)

      NotificationSystem.publish("bench.latency", %{
        send_time: send_time
      })

      receive do
        {:latency, latency} -> latency
      after
        1000 -> nil  # Timeout
      end
    end)
    |> Enum.reject(&is_nil/1)

    # Izracunavanje statistike
    sorted = Enum.sort(latencies)
    count = length(sorted)

    result = if count > 0 do
      %{
        samples: count,
        min_us: Enum.min(sorted),
        max_us: Enum.max(sorted),
        avg_us: div(Enum.sum(sorted), count),
        p50_us: percentile(sorted, 0.5),
        p95_us: percentile(sorted, 0.95),
        p99_us: percentile(sorted, 0.99),
        min_ms: Enum.min(sorted) / 1000,
        avg_ms: Enum.sum(sorted) / count / 1000,
        p50_ms: percentile(sorted, 0.5) / 1000,
        p95_ms: percentile(sorted, 0.95) / 1000,
        p99_ms: percentile(sorted, 0.99) / 1000
      }
    else
      %{error: "No latency samples collected"}
    end

    if Map.has_key?(result, :avg_ms) do
      IO.puts("Average: #{Float.round(result.avg_ms, 3)} ms")
      IO.puts("P50: #{Float.round(result.p50_ms, 3)} ms")
      IO.puts("P95: #{Float.round(result.p95_ms, 3)} ms")
      IO.puts("P99: #{Float.round(result.p99_ms, 3)} ms\n")
    end

    result
  end

  @doc """
  Benchmarks skalabilnosti sa povecanjem broja subs.
  """
  def benchmark_scalability(opts \\ []) do
    message_count = Keyword.get(opts, :messages, 1_000)
    subscriber_steps = Keyword.get(opts, :steps, [10, 50, 100, 500, 1000])

    IO.puts("Scalability Benchmark")
    IO.puts("Messages per test: #{message_count}")

    results = Enum.map(subscriber_steps, fn subscriber_count ->
      IO.puts("Testing with #{subscriber_count} subscribers...")

      # Kreiranje subs
      SubscriberManager.create_multiple_subscribers(
        subscriber_count,
        [topics: ["bench.scalability"]]
      )

      Process.sleep(200)

      # Merenje throughput
      start_time = System.monotonic_time(:millisecond)

      1..message_count
      |> Enum.each(fn i ->
        NotificationSystem.publish("bench.scalability", %{index: i})
      end)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      throughput = (message_count / elapsed_ms) * 1000

      %{
        subscribers: subscriber_count,
        throughput: Float.round(throughput, 2),
        elapsed_ms: elapsed_ms
      }
    end)

    IO.puts("\nScalability results:")
    Enum.each(results, fn r ->
      IO.puts("    #{r.subscribers} subs: #{r.throughput} msg/s")
    end)
    IO.puts("")

    results
  end

  @doc """
  Benchmarks performansi sa concurrent publishers.
  """
  def benchmark_concurrent_publishers(opts \\ []) do
    publishers = Keyword.get(opts, :publishers, [1, 2, 4, 8])
    messages_per_publisher = Keyword.get(opts, :messages_per_publisher, 1_000)

    IO.puts("Concurrent publishers Benchmark")

    results = Enum.map(publishers, fn pub_count ->
      IO.puts("Testing with #{pub_count} concurrent publishers...")

      # Kreiranje subscribers
      SubscriberManager.create_multiple_subscribers(
        50,
        [topics: ["bench.concurrent"]]
      )

      Process.sleep(200)

      # Pokretanje publishers
      test_pid = self()
      start_time = System.monotonic_time(:millisecond)

      tasks = Enum.map(1..pub_count, fn pub_id ->
        Task.async(fn ->
          1..messages_per_publisher
          |> Enum.each(fn i ->
            NotificationSystem.publish("bench.concurrent", %{
              publisher: pub_id,
              index: i
            })
          end)

          send(test_pid, {:publisher_done, pub_id})
        end)
      end)

      # Cekanje na sve publishers
      Task.await_many(tasks, 30_000)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time
      total_messages = pub_count * messages_per_publisher
      throughput = (total_messages / elapsed_ms) * 1000

      %{
        publishers: pub_count,
        total_messages: total_messages,
        elapsed_ms: elapsed_ms,
        throughput: Float.round(throughput, 2)
      }
    end)

    IO.puts("\nConcurrent publisher Results:")
    Enum.each(results, fn r ->
      IO.puts("#{r.publishers} publishers: #{r.throughput} msg/s")
    end)
    IO.puts("")

    results
  end

  @doc """
  Poredjenje perfomansi sa i bez persistence.
  """
  def compare_persistence do
    IO.puts("\nPersistence impact comparison")

    message_count = 5_000

    # Sa persistence
    IO.puts("Testing WITHOUT persistence...")
    start_time = System.monotonic_time(:millisecond)

    1..message_count
    |> Enum.each(fn i ->
      NotificationSystem.publish("bench.test", %{index: i})
    end)

    without_persistence_ms = System.monotonic_time(:millisecond) - start_time

    # Bez persistence
    IO.puts("Testing WITH persistence...")
    start_time = System.monotonic_time(:millisecond)

    1..message_count
    |> Enum.each(fn i ->
      NotificationSystem.Persistence.store_message("bench.test", %{index: i})
      NotificationSystem.publish("bench.test", %{index: i})
    end)

    with_persistence_ms = System.monotonic_time(:millisecond) - start_time

    overhead = Float.round((with_persistence_ms - without_persistence_ms) / without_persistence_ms * 100, 2)

    result = %{
      without_persistence_ms: without_persistence_ms,
      with_persistence_ms: with_persistence_ms,
      overhead_percent: overhead
    }

    IO.puts("\nResults:")
    IO.puts("Without: #{without_persistence_ms} ms")
    IO.puts("With: #{with_persistence_ms} ms")
    IO.puts("Overhead: #{overhead}%\n")

    result
  end

  # Private functions

  defp collect_system_info do
    %{
      node: Node.self(),
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      erts_version: :erlang.system_info(:version) |> to_string(),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_limit: :erlang.system_info(:process_limit),
      process_count: :erlang.system_info(:process_count),
      memory: memory_info()
    }
  end

  defp memory_info do
    memory = :erlang.memory()

    %{
      total_mb: Float.round(memory[:total] / 1_048_576, 2),
      processes_mb: Float.round(memory[:processes] / 1_048_576, 2),
      ets_mb: Float.round(memory[:ets] / 1_048_576, 2),
      atom_mb: Float.round(memory[:atom] / 1_048_576, 2)
    }
  end

  defp percentile(sorted_list, percentile) do
    count = length(sorted_list)
    index = round(percentile * count) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_list, index)
  end

  defp print_report(results) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("BENCHMARK SUMMARY")
    IO.puts(String.duplicate("=", 70))

    IO.puts("\nSystem Information:")
    info = results.system_info
    IO.puts("Node: #{info.node}")
    IO.puts("OTP: #{info.otp_release}, ERTS: #{info.erts_version}")
    IO.puts("Schedulers: #{info.schedulers_online}/#{info.schedulers}")
    IO.puts("Processes: #{info.process_count}/#{info.process_limit}")
    IO.puts("Memory: #{info.memory.total_mb} MB (processes: #{info.memory.processes_mb} MB)")

    IO.puts("\nKey Metrics:")
    IO.puts("Peak Throughput: #{results.throughput.throughput_per_sec} msg/s")
    IO.puts("Median Latency: #{Float.round(results.latency.p50_ms, 3)} ms")
    IO.puts("P95 Latency: #{Float.round(results.latency.p95_ms, 3)} ms")

    IO.puts("\n" <> String.duplicate("=", 70) <> "\n")
  end
end
