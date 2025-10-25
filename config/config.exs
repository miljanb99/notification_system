import Config

# Konfiguracija loggera
config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Konfiguracija za distributed Erlang
config :notification_system,
  # Interval za monitoring checks
  monitor_interval: 30_000,

  # Maximum broj subscribera (za resource limiting)
  max_subscribers: 10_000

# Development environment
if config_env() == :dev do
  config :logger, level: :debug
end

# Test environment
if config_env() == :test do
  config :logger, level: :warning
end
