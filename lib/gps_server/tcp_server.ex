defmodule GpsServer.TcpServer do
  use GenServer
  require Logger

  @receive_timeout 60_000 # Increased timeout

  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    name = Module.concat(__MODULE__, to_string(port))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    protocol_name = Keyword.fetch!(opts, :protocol)
    # This gets the base namespace, e.g., GpsServer.Protocols.Topflytech
    protocol_handler_namespace = Module.concat(GpsServer.Protocols, Macro.camelize(to_string(protocol_name)))

    task_supervisor_name = Module.concat(__MODULE__.TaskSupervisor, to_string(port))
    {:ok, task_sup} = Task.Supervisor.start_link(name: task_supervisor_name)

    socket_opts = [:binary, active: false, reuseaddr: true]

    case :gen_tcp.listen(port, socket_opts) do
      {:ok, listen_socket} ->
        Logger.info("TCP listener started on port #{port} for protocol :#{protocol_name}")
        parent = self()
        spawn_link(fn -> accept_loop(parent, listen_socket) end)
        {:ok, %{protocol_handler_namespace: protocol_handler_namespace, task_supervisor: task_sup, port: port, protocol_name: protocol_name}}
      {:error, reason} ->
        Logger.error("Failed to start listener on port #{port}: #{:inet.format_error(reason)}")
        {:stop, reason}
    end
  end

  defp accept_loop(parent, listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        GenServer.cast(parent, {:accept, socket})
        accept_loop(parent, listen_socket)
      {:error, reason} ->
        Logger.error("Error accepting connection: #{:inet.format_error(reason)}")
    end
  end

  @impl true
  def handle_cast({:accept, socket}, state) do
    {:ok, {ip, port}} = :inet.peername(socket)
    peer = "#{:inet.ntoa(ip) |> IO.iodata_to_binary()}:#{port}" |> IO.iodata_to_binary()
    Logger.info("Connection accepted from #{peer}", port: state.port, protocol: state.protocol_name, peer: peer)
    Task.Supervisor.start_child(state.task_supervisor, fn -> handle_connection(socket, peer, state) end)
    {:noreply, state}
  end

  defp handle_connection(socket, peer, state) do
    # Construct the full handler module name, e.g., GpsServer.Protocols.Topflytech.Handler
    handler_module = Module.concat(state.protocol_handler_namespace, "Handler")
    try do
      Logger.info("Setting metadata: port=#{state.port}, protocol=#{state.protocol_name}, peer=#{peer}")
      Logger.metadata(port: state.port, protocol: state.protocol_name, peer: peer)
      # Start the framing loop with an empty buffer
      frame_loop(socket, handler_module, <<>>)
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        reason_str = reason |> inspect() |> IO.iodata_to_binary()
        Logger.error("Connection task crashed. Peer: #{peer}, Reason: #{kind}: #{reason_str}\nStacktrace:\n#{Exception.format_stacktrace(stacktrace)}")
    after
      :gen_tcp.close(socket)
      Logger.info("Connection closed for peer: #{peer}")
    end
  end

  # The new framing loop
  defp frame_loop(socket, handler, buffer) do
    case :gen_tcp.recv(socket, 0, @receive_timeout) do
      {:ok, data} ->
        new_buffer = buffer <> data
        Logger.info("Received #{byte_size(data)} bytes. Buffer size: #{byte_size(new_buffer)} bytes.")
        process_buffer(socket, handler, new_buffer)

      {:error, :timeout} ->
        Logger.info("Connection timed out. Closing.")
        :ok # End the loop

      {:error, reason} ->
        Logger.warning("Socket receive error: #{:inet.format_error(reason)}. Closing.")
        :ok # End the loop
    end
  end

  # Base case for the recursive buffer processing
  defp process_buffer(socket, handler, <<>>) do
    # The buffer is empty, so we wait for more data.
    frame_loop(socket, handler, <<>>)
  end

  # Process the buffer to find and handle complete packets
  defp process_buffer(socket, handler, buffer) do
    Logger.info("Processing buffer with handler: #{inspect(handler)}")
    case handler.frame(buffer) do
      {:ok, frame, rest} ->
        # Pass the socket to the handler so it can send a response
        handler.handle_data(frame, socket)
        # Immediately try to process the rest of the buffer
        process_buffer(socket, handler, rest)

      {:more, _} ->
        Logger.info("Buffer contains incomplete frame. Waiting for more data.")
        # Continue the loop, waiting for more data
        frame_loop(socket, handler, buffer)

      {:error, reason} ->
        Logger.error("Framing error: #{reason |> inspect() |> IO.iodata_to_binary()}")
        frame_loop(socket, handler, <<>>)
    end
  end
end
