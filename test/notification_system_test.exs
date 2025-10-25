defmodule NotificationSystemTest do
  use ExUnit.Case
  doctest NotificationSystem

  setup do
    # Čisti state između testova
    :ok
  end

  describe "Publisher/Subscriber basic flow" do
    test "subscriber receives published message" do
      # Kreiraj testni subscriber sa test process kao handlerom
      test_pid = self()
      
      handler = fn topic, message ->
        send(test_pid, {:received, topic, message})
      end
      
      {:ok, _sub_pid} = NotificationSystem.subscribe("test_sub", ["test.topic"], handler)
      
      # Sačekaj da se subscriber registruje
      Process.sleep(50)
      
      # Pošalji poruku
      NotificationSystem.publish("test.topic", %{data: "test message"})
      
      # Verifikuj prijem
      assert_receive {:received, "test.topic", %{data: "test message"}}, 1000
    end

    test "multiple subscribers receive same message" do
      test_pid = self()
      
      handler = fn topic, message ->
        send(test_pid, {:received, self(), topic, message})
      end
      
      # Kreiraj 3 subscribera za istu temu
      {:ok, sub1} = NotificationSystem.subscribe("sub1", ["common.topic"], handler)
      {:ok, sub2} = NotificationSystem.subscribe("sub2", ["common.topic"], handler)
      {:ok, sub3} = NotificationSystem.subscribe("sub3", ["common.topic"], handler)
      
      Process.sleep(50)
      
      # Pošalji poruku
      NotificationSystem.publish("common.topic", %{id: 1})
      
      # Svi bi trebalo da prime poruku
      assert_receive {:received, ^sub1, "common.topic", %{id: 1}}, 1000
      assert_receive {:received, ^sub2, "common.topic", %{id: 1}}, 1000
      assert_receive {:received, ^sub3, "common.topic", %{id: 1}}, 1000
    end

    test "subscriber only receives messages for subscribed topics" do
      test_pid = self()
      
      handler = fn topic, message ->
        send(test_pid, {:received, topic, message})
      end
      
      {:ok, _pid} = NotificationSystem.subscribe("selective_sub", ["topic.a"], handler)
      
      Process.sleep(50)
      
      # Pošalji na subscribed topic
      NotificationSystem.publish("topic.a", %{data: "for A"})
      
      # Pošalji na non-subscribed topic
      NotificationSystem.publish("topic.b", %{data: "for B"})
      
      # Samo topic.a bi trebalo da stigne
      assert_receive {:received, "topic.a", %{data: "for A"}}, 1000
      refute_receive {:received, "topic.b", _}, 500
    end
  end

  describe "Broker statistics" do
    test "tracks message count" do
      initial_stats = NotificationSystem.broker_stats()
      initial_count = initial_stats.messages_sent
      
      # Pošalji nekoliko poruka
      NotificationSystem.publish("stats.test", %{msg: 1})
      NotificationSystem.publish("stats.test", %{msg: 2})
      NotificationSystem.publish("stats.test", %{msg: 3})
      
      Process.sleep(50)
      
      final_stats = NotificationSystem.broker_stats()
      
      assert final_stats.messages_sent == initial_count + 3
    end

    test "reports node information" do
      stats = NotificationSystem.broker_stats()
      
      assert is_atom(stats.node)
      assert is_integer(stats.messages_sent)
      assert is_integer(stats.total_subscribers)
      assert is_integer(stats.uptime_seconds)
    end
  end

  describe "Broadcast functionality" do
    test "broadcast sends to all topics" do
      test_pid = self()
      
      handler = fn _topic, message ->
        send(test_pid, {:broadcast_received, message})
      end
      
      # Kreiraj subscribere na različite teme
      {:ok, _} = NotificationSystem.subscribe("broad1", ["topic.x"], handler)
      {:ok, _} = NotificationSystem.subscribe("broad2", ["topic.y"], handler)
      
      Process.sleep(50)
      
      # Broadcast
      NotificationSystem.broadcast(%{announcement: "important"})
      
      Process.sleep(100)
      
      # Oba subscribera bi trebalo da prime broadcast
      assert_receive {:broadcast_received, %{announcement: "important"}}, 1000
      assert_receive {:broadcast_received, %{announcement: "important"}}, 1000
    end
  end

  describe "Topic management" do
    test "lists active topics" do
      # Kreiraj subscribere za različite teme
      {:ok, _} = NotificationSystem.subscribe("t1", ["unique.topic.1"])
      {:ok, _} = NotificationSystem.subscribe("t2", ["unique.topic.2"])
      
      Process.sleep(50)
      
      topics = NotificationSystem.list_topics()
      
      assert "unique.topic.1" in topics
      assert "unique.topic.2" in topics
    end

    test "counts subscribers per topic" do
      # Subscriberi za istu temu
      {:ok, _} = NotificationSystem.subscribe("c1", ["count.test"])
      {:ok, _} = NotificationSystem.subscribe("c2", ["count.test"])
      {:ok, _} = NotificationSystem.subscribe("c3", ["count.test"])
      
      Process.sleep(50)
      
      count = NotificationSystem.count_subscribers("count.test")
      
      assert count == 3
    end
  end

  describe "Fault tolerance" do
    test "system continues after subscriber crash" do
      test_pid = self()
      
      # Handler koji će baciti grešku na određenu poruku
      crash_handler = fn _topic, %{crash: true} ->
        raise "Simulated crash"
      end
      
      normal_handler = fn topic, message ->
        send(test_pid, {:received, topic, message})
      end
      
      # Subscriber koji će pasti
      {:ok, crash_sub} = NotificationSystem.subscribe("crasher", ["crash.topic"], crash_handler)
      
      # Normalni subscriber
      {:ok, _normal_sub} = NotificationSystem.subscribe("normal", ["crash.topic"], normal_handler)
      
      Process.sleep(50)
      
      # Pošalji poruku koja izaziva crash
      NotificationSystem.publish("crash.topic", %{crash: true})
      
      Process.sleep(100)
      
      # Pošalji normalnu poruku
      NotificationSystem.publish("crash.topic", %{crash: false})
      
      # Normalni subscriber bi trebalo da primi poruku uprkos crash-u drugog
      assert_receive {:received, "crash.topic", %{crash: false}}, 1000
    end
  end

  describe "Performance" do
    @tag :performance
    test "handles multiple subscribers efficiently" do
      count = 100
      
      start_time = System.monotonic_time(:millisecond)
      
      # Kreiraj mnogo subscribera
      1..count
      |> Enum.each(fn i ->
        NotificationSystem.subscribe("perf_sub_#{i}", ["perf.test"])
      end)
      
      creation_time = System.monotonic_time(:millisecond) - start_time
      
      # Kreiranje 100 subscribera bi trebalo biti brzo (< 1 sekunda)
      assert creation_time < 1000
      
      Process.sleep(100)
      
      # Pošalji poruku
      message_start = System.monotonic_time(:millisecond)
      NotificationSystem.publish("perf.test", %{data: "performance test"})
      message_time = System.monotonic_time(:millisecond) - message_start
      
      # Slanje bi trebalo biti instant
      assert message_time < 100
    end
  end
end
