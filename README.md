# Distributed Notification System in Elixir

A distributed publish-subscribe notification system implemented in Elixir using OTP principles. This project demonstrates advanced concepts in concurrent and distributed systems programming.

## Features

- **Actor Model Concurrency**: Thousands of independent processes
- **Fault Tolerance**: Supervision trees with automatic process restart
- **Distributed Computing**: Multi-node communication
- **Message Persistence**: Mnesia distributed database
- **Delivery Guarantees**: At-least-once delivery with acknowledgments
- **Dead Letter Queue**: Failed message handling
- **Priority Routing**: Content-based filtering
- **Rate Limiting**: Token bucket algorithm
- **End-to-End Encryption**: AES-256-GCM
- **Performance Metrics**: Prometheus-compatible export

## Requirements

- Elixir 1.14+
- Erlang/OTP 24+

## Installation

```bash
# Clone the repository
git clone https://github.com//notification_system.git
cd notification_system

# Install dependencies
mix deps.get

# Compile project
mix compile
```

## Quick Start

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

## Running Tests

```bash
mix test
```

## Distributed Mode

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

## Advanced Features

### Message Persistence

```elixir
NotificationSystem.publish("orders", %{id: 1}, persist: true, priority: 8)
```

### Priority Routing

```elixir
NotificationSystem.publish("urgent", %{alert: "critical"},
  priority: 10,
  use_router: true
)
```

### Content Filtering

```elixir
NotificationSystem.add_routing_rule("premium", fn msg ->
  Map.get(msg, :tier) == :premium
end)
```

### Message Encryption

```elixir
key = NotificationSystem.generate_key()
NotificationSystem.publish("secure", %{secret: "data"},
  encrypt: true,
  key: key
)
```

### Performance Benchmarking

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

## Project Structure

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
