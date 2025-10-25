defmodule NotificationSystem.RateLimiter do
  @moduledoc """
  Mehanizam za ogranicavanje ucestalosti i kontrolu.

  Funkcionalnosti:
  - Token bucket algoritam
  - Ogranicenje po temi (topic)
  - Globalno ogranicenje
  - Signalizacija
  - Upravljanje redom
  """
  use GenServer
  require Logger

  @refill_interval 1_000
  @default_rate 1000
  @default_burst 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Proverava da li poruka moze biti objavljena.
  Vraca {:ok, :allowed} ili {:error, :rate_limited}.
  """
  def check_rate(topic) do
    GenServer.call(__MODULE__, {:check_rate, topic})
  end

  @doc """
  Konfigurise rate limit za specific topic
  """
  def configure_topic(topic, rate, burst) do
    GenServer.call(__MODULE__, {:configure, topic, rate, burst})
  end

  @doc """
  Dohvata trenutnu statistiku za rate limiter
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Resetuje sve rate limit-e za topic
  """
  def reset(topic) do
    GenServer.cast(__MODULE__, {:reset, topic})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    global_rate = Keyword.get(opts, :global_rate, @default_rate)
    global_burst = Keyword.get(opts, :global_burst, @default_burst)

    schedule_refill()

    state = %{
      global: %{
        rate: global_rate,
        burst: global_burst,
        tokens: global_burst,
        last_refill: System.monotonic_time(:millisecond)
      },
      topics: %{},
      stats: %{
        total_allowed: 0,
        total_rejected: 0,
        rejected_by_topic: %{}
      }
    }

    Logger.info("Rate limiter started: #{global_rate} msg/s, burst: #{global_burst}")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_rate, topic}, _from, state) do
    # Provera globalnog rate limit-a
    case check_bucket(state.global) do
      :rate_limited ->
        new_stats = update_rejection_stats(state.stats, :global)
        Logger.debug("Global rate limit exceeded")
        {:reply, {:error, :rate_limited}, %{state | stats: new_stats}}

      {:ok, new_global} ->
        # Provera topic-specific rate limit-a
        topic_bucket = Map.get(state.topics, topic, create_default_bucket())

        case check_bucket(topic_bucket) do
          :rate_limited ->
            new_stats = update_rejection_stats(state.stats, topic)
            Logger.debug("Topic rate limit exceeded: #{topic}")
            {:reply, {:error, :rate_limited}, %{state | stats: new_stats}}

          {:ok, new_topic_bucket} ->
            new_topics = Map.put(state.topics, topic, new_topic_bucket)
            new_stats = %{state.stats | total_allowed: state.stats.total_allowed + 1}

            {:reply, {:ok, :allowed}, %{
              state |
              global: new_global,
              topics: new_topics,
              stats: new_stats
            }}
        end
    end
  end

  @impl true
  def handle_call({:configure, topic, rate, burst}, _from, state) do
    bucket = %{
      rate: rate,
      burst: burst,
      tokens: burst,
      last_refill: System.monotonic_time(:millisecond)
    }

    new_topics = Map.put(state.topics, topic, bucket)
    Logger.info("Configured rate limit for #{topic}: #{rate} msg/s, burst: #{burst}")

    {:reply, :ok, %{state | topics: new_topics}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    topic_stats = Enum.map(state.topics, fn {topic, bucket} ->
      {topic, %{
        rate: bucket.rate,
        burst: bucket.burst,
        available_tokens: bucket.tokens
      }}
    end) |> Enum.into(%{})

    stats = Map.merge(state.stats, %{
      global_available_tokens: state.global.tokens,
      global_rate: state.global.rate,
      topic_limits: topic_stats,
      rejection_rate: calculate_rejection_rate(state.stats)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:reset, topic}, state) do
    new_topics = case topic do
      :all -> %{}
      _ -> Map.delete(state.topics, topic)
    end

    {:noreply, %{state | topics: new_topics}}
  end

  @impl true
  def handle_info(:refill, state) do
    now = System.monotonic_time(:millisecond)

    # Refill global bucket
    new_global = refill_bucket(state.global, now)

    # Refill all topic buckets
    new_topics = Enum.map(state.topics, fn {topic, bucket} ->
      {topic, refill_bucket(bucket, now)}
    end) |> Enum.into(%{})

    schedule_refill()
    {:noreply, %{state | global: new_global, topics: new_topics}}
  end

  # Private functions

  defp create_default_bucket do
    %{
      rate: @default_rate,
      burst: @default_burst,
      tokens: @default_burst,
      last_refill: System.monotonic_time(:millisecond)
    }
  end

  defp check_bucket(%{tokens: tokens} = bucket) when tokens >= 1 do
    {:ok, %{bucket | tokens: tokens - 1}}
  end

  defp check_bucket(_bucket), do: :rate_limited

  defp refill_bucket(bucket, now) do
    elapsed_ms = now - bucket.last_refill
    elapsed_seconds = elapsed_ms / 1000

    tokens_to_add = elapsed_seconds * bucket.rate

    new_tokens = min(bucket.tokens + tokens_to_add, bucket.burst)

    %{bucket | tokens: new_tokens, last_refill: now}
  end

  defp update_rejection_stats(stats, topic) do
    rejected_by_topic = Map.update(stats.rejected_by_topic, topic, 1, &(&1 + 1))

    %{stats |
      total_rejected: stats.total_rejected + 1,
      rejected_by_topic: rejected_by_topic
    }
  end

  defp calculate_rejection_rate(stats) do
    total = stats.total_allowed + stats.total_rejected
    if total > 0 do
      Float.round(stats.total_rejected / total * 100, 2)
    else
      0.0
    end
  end

  defp schedule_refill do
    Process.send_after(self(), :refill, @refill_interval)
  end
end
