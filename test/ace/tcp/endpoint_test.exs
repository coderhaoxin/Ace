defmodule CounterServer do
  def init(_, num) do
    {:nosend, num}
  end

  def handle_packet(_, last) do
    count = last + 1
    {:send, "#{count}\r\n", count}
  end

  def handle_info(_, last) do
    {:nosend, last}
  end

  def terminate(_, _) do
    :ok
  end
end

defmodule GreetingServer do
  def init(_, message) do
    {:send, "#{message}\r\n", []}
  end

  def terminate(_reason, _state) do
    IO.puts("Socket connection closed")
  end
end

defmodule EchoServer do
  def init(_, state) do
    {:nosend, state}
  end

  def handle_packet(inbound, state) do
    {:send, "ECHO: #{String.strip(inbound)}\r\n", state}
  end
end

defmodule BroadcastServer do
  def init(_, pid) do
    send(pid, {:register, self})
    {:nosend, pid}
  end

  def handle_info({:notify, notification}, state) do
    {:send, "#{notification}\r\n", state}
  end
end

defmodule Ace.TCP.EndpointTest do
  use ExUnit.Case, async: true

  test "echos each message" do
    port = 10001
    {:ok, _server} = Ace.TCP.Endpoint.start_link({EchoServer, []}, port: port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\r\n")
    assert {:ok, "ECHO: blob\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "says welcome for new connection" do
    port = 10002
    {:ok, _server} = Ace.TCP.Endpoint.start_link({GreetingServer, "WELCOME"}, port: port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert {:ok, "WELCOME\r\n"} = :gen_tcp.recv(client, 0, 2000)
  end

  test "socket broadcasts server message" do
    port = 10_003
    {:ok, _server} = Ace.TCP.Endpoint.start_link({BroadcastServer, self}, port: port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, {:notify, "HELLO"})
      end
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "state is passed through messages" do
    port = 10_004
    {:ok, _server} = Ace.TCP.Endpoint.start_link({CounterServer, 0}, port: port)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client, 0)
    :ok = :gen_tcp.send(client, "anything\r\n")
    assert {:ok, "2\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "start multiple connections" do
    port = 10_005
    {:ok, _endpoint} = Ace.TCP.Endpoint.start_link({CounterServer, 0}, port: port)
    {:ok, client1} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, client2} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client1, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client1, 0)
    :ok = :gen_tcp.send(client2, "anything\r\n")
    assert {:ok, "1\r\n"} = :gen_tcp.recv(client2, 0)
  end

  test "can fetch the listened to port from an endpoint" do
    port = 10_006
    {:ok, endpoint} = Ace.TCP.Endpoint.start_link({EchoServer, []}, port: port)
    assert {:ok, port} == Ace.TCP.Endpoint.port(endpoint)
  end

  test "will show OS allocated port" do
    port = 0
    {:ok, endpoint} = Ace.TCP.Endpoint.start_link({EchoServer, []}, port: port)
    {:ok, port} = Ace.TCP.Endpoint.port(endpoint)
    assert port > 10_000
  end
end
