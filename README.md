# Distributed Notification System in Elixir

A distributed publish-subscribe notification system implemented in Elixir using OTP principles. This project demonstrates advanced concepts in concurrent and distributed systems programming.

## Features

- **Actor model concurrency**: Thousands of independent processes
- **Fault tolerance**: Supervision trees with automatic process restart
- **Distributed computing**: Multi-node communication
- **Message persistence**: Mnesia distributed database
- **Delivery guarantees**: At-least-once delivery with acknowledgments
- **Dead letter queue**: Failed message handling
- **Priority routing**: Content-based filtering
- **Rate limiting**: Token bucket algorithm
- **End-to-End encryption**: AES-256-GCM
- **Performance metrics**: Prometheus-compatible export

## Requirements

- Elixir 1.14+
- Erlang/OTP 24+

## Installation

```bash
# Clone the repository
git clone git@github.com:miljanb99/notification_system.git
cd notification_system

# Install dependencies
mix deps.get

# Compile project
mix compile
```

## Quick start

```bash
# Start interactive shell
iex -S mix
```

```elixir
# Create a subscriber
{:ok, sub} = NotificationSystem.subscribe("my_sub", ["orders"])

# Publish a message
NotificationSystem.publish("orders", %{order_id: 123, amount: 99.99})

# Check statistics
NotificationSystem.stats()
```

## Running tests

```bash
mix test
```

## Distributed mode

Start multiple nodes:

```bash
# Terminal 1
iex --name node1@127.0.0.1 --cookie secret -S mix

# Terminal 2
iex --name node2@127.0.0.1 --cookie secret -S mix
```

Then connect nodes:

```elixir
# In node2
NotificationSystem.connect_node(:"node1@127.0.0.1")

# Publish to all nodes
NotificationSystem.global_publish("cluster_topic", %{data: "hello"})
```

## Advanced features

### Message persistence

```elixir
NotificationSystem.publish("orders", %{id: 1}, persist: true, priority: 8)
```

### Priority routing

```elixir
NotificationSystem.publish("urgent", %{alert: "critical"},
  priority: 10,
  use_router: true
)
```

### Content filtering

```elixir
NotificationSystem.add_routing_rule("premium", fn msg ->
  Map.get(msg, :tier) == :premium
end)
```

### Message encryption

```elixir
key = NotificationSystem.generate_key()
NotificationSystem.publish("secure", %{secret: "data"},
  encrypt: true,
  key: key
)
```

### Performance benchmarking

```elixir
NotificationSystem.benchmark()
```

## Architecture

```
Application Supervisor
├── Registry (pub/sub pattern)
├── RateLimiter (token bucket)
├── Metrics (performance tracking)
├── Router (priority queues)
├── Broker (message dispatcher)
├── Acknowledgment (retry logic)
├── DeadLetterQueue (failed messages)
├── DynamicSupervisor (subscriber management)
└── Monitor (system telemetry)
```

## Performance

Typical benchmarks on modern hardware:

- **Throughput**: 8,000-12,000 messages/second
- **Latency**: P50: 0.5ms, P95: 2ms, P99: 5ms
- **Scalability**: Linear up to ~1000 subscribers
- **Memory**: ~2KB per subscriber process

## Project structure

```
notification_system/
├── lib/
│   ├── notification_system.ex
│   └── notification_system/
│       ├── application.ex
│       ├── broker.ex
│       ├── subscriber.ex
│       ├── publisher.ex
│       ├── persistence.ex
│       ├── rate_limiter.ex
│       ├── router.ex
│       ├── acknowledgment.ex
│       ├── dead_letter_queue.ex
│       ├── metrics.ex
│       └── encryption.ex
├── test/
│   └── notification_system_test.exs
├── config/
│   └── config.exs
└── mix.exs
```

## Author

Miljan Bakić
Broj indeksa: 1033/2023
Smer: Informatika
Kurs: Dizajn programskih jezika
Datum: 11. Oktobar, 2025
