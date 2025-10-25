defmodule NotificationSystem.ClusterManager do
  @moduledoc """
  Upravlja komunikacijom između nodova (nodes) u distribuiranom sistemu.
  """
  require Logger

  def connect_node(node) when is_atom(node) do
    case Node.connect(node) do
      true ->
        Logger.info("Successfully connected to node: #{node}")
        :ok

      false ->
        Logger.error("Failed to connect to node: #{node}")
        {:error, :connection_failed}

      :ignored ->
        Logger.warning("Node connection ignored (local node?)")
        {:error, :ignored}
    end
  end

  def list_nodes do
    [Node.self() | Node.list()]
  end

  def node_count do
    length(list_nodes())
  end

  def global_publish(topic, message) do
    nodes = list_nodes()

    Enum.each(nodes, fn node ->
      :rpc.call(node, NotificationSystem.Broker, :publish, [topic, message])
    end)

    Logger.info("Published to #{length(nodes)} nodes")
    :ok
  end

  def global_stats do
    nodes = list_nodes()

    Enum.map(nodes, fn node ->
      case :rpc.call(node, NotificationSystem.Broker, :stats, [], 5000) do
        {:badrpc, reason} ->
          %{node: node, error: reason}

        stats ->
          stats
      end
    end)
  end

  def ping_all_nodes do
    Node.list()
    |> Enum.map(fn node ->
      case Node.ping(node) do
        :pong -> {node, :connected}
        :pang -> {node, :disconnected}
      end
    end)
    |> Enum.into(%{})
  end
end
