defmodule NotificationSystem.SubscriberManager do
  @moduledoc """
  Upravlja dinamickim kreiranjem i zivotnim ciklusom subscribera.
  Koristi DynamicSupervisor za fault tolerance.
  """
  require Logger

  @supervisor NotificationSystem.SubscriberSupervisor

  @doc """
  Kreira novog subscribera pod supervision tree-om.

  ## Opcije
  - :name - jedinstveno ime subscribera
  - :topics - lista tema za pracenje
  - :handler - callback funkcija (opcionalno)

  ## Primer

      NotificationSystem.SubscriberManager.create_subscriber(
        name: "user_notifications",
        topics: ["user.login", "user.logout"],
        handler: fn topic, msg -> IO.puts("Got: \#{inspect(msg)}") end
      )
  """
  def create_subscriber(opts) do
    spec = {NotificationSystem.Subscriber, opts}

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:ok, pid} ->
        Logger.info("Created subscriber: #{inspect(Keyword.get(opts, :name))}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.warn("Subscriber already exists")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to create subscriber: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Zaustavlja subscribera
  """
  def stop_subscriber(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(@supervisor, pid)
  end

  @doc """
  Vraca listu svih aktivnih subscribera
  """
  def list_subscribers do
    DynamicSupervisor.which_children(@supervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  @doc """
  Vraca broj aktivnih subscribera
  """
  def count_subscribers do
    DynamicSupervisor.count_children(@supervisor).active
  end

  @doc """
  Kreira vise subscribera odjednom (za testiranje skalabilnosti)
  """
  def create_multiple_subscribers(count, base_opts \\ []) do
    1..count
    |> Enum.map(fn i ->
      opts = Keyword.merge(base_opts, [name: "subscriber_#{i}"])
      create_subscriber(opts)
    end)
  end
end
