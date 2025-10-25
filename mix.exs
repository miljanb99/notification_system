defmodule NotificationSystem.MixProject do
  use Mix.Project

  def project do
    [
      app: :notification_system,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia, :crypto],
      mod: {NotificationSystem.Application, []}
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.3"}
    ]
  end
end
