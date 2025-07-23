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
    protocol_handler_namespace = Module.concat(GpsServer.Protocols, Macro.camelize(to_string(protocol_name)))

    # SUGGESTION: Validate the handler module on startup for fail-fast behavior.
    case validate_handler(protocol_handler_namespace) do
      {:ok, handler_module} ->
        task_supervisor_name = Module.concat(__MODULE__.TaskSupervisor, to_string(port))
        {:ok, task_sup} = Task.Supervisor.start_link(name: task_supervisor_name)

        socket_opts = [:binary, active: false, reuseaddr: true]

        case :gen_tcp.listen(port, socket_opts) do
          {:ok, listen_socket} ->
            Logger.info("TCP listener started on port #{port} for protocol :#{protocol_name}")
            parent = self()
            spawn_link(fn -> accept_loop(parent, listen_socket) end)
            state = %{handler_module: handler_module, task_supervisor: task_sup, port: port, protocol_name: protocol_name}
            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to start listener on port #{port}: #{:inet.format_error(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("Invalid handler for protocol :#{protocol_name}. Reason: #{reason}")
        {:stop, {:invalid_handler, reason}}
    end
  end

  # Helper to ensure the handler module is valid before we start listening.
  defp validate_handler(namespace) do
    handler_module = Module.concat(namespace, "Handler")

    if Code.ensure_loaded?(handler_module) do
      if function_exported?(handler_module, :frame, 1) and function_exported?(handler_module, :handle_data, 2) do
        {:ok, handler_module}
      else
        {:error, "does not export frame/1 or handle_data/2"}
      end
    else
      {:error, "module #{inspect(handler_module)} not found"}
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
    peer = "#{:inet.ntoa(ip) |> to_string()}:#{port}"
    Logger.info("Connection accepted from #{peer}", port: state.port, protocol: state.protocol_name, peer: peer)
    Task.Supervisor.start_child(state.task_supervisor, fn -> handle_connection(socket, peer, state) end)
    {:noreply, state}
  end

  defp handle_connection(socket, peer, state) do
    try do
      Logger.metadata(port: state.port, protocol: state.protocol_name, peer: peer)
      frame_loop(socket, state.handler_module, <<>>)
    catch
      kind, reason ->
        Logger.error(
          "Connection task crashed. Peer: #{peer}, Reason: #{kind}: #{inspect(reason)}\nStacktrace:\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )
    after
      :gen_tcp.close(socket)
      Logger.info("Connection closed for peer: #{peer}")
    end
  end

  defp frame_loop(socket, handler, buffer) do
    case :gen_tcp.recv(socket, 0, @receive_timeout) do
      {:ok, data} ->
        new_buffer = buffer <> data
        # SUGGESTION: Changed to :debug to avoid flooding production logs.
        Logger.debug("Received #{byte_size(data)} bytes. Buffer size: #{byte_size(new_buffer)} bytes.")
        process_buffer(socket, handler, new_buffer)

      {:error, :timeout} ->
        Logger.info("Connection timed out. Closing.")
        :ok # End the loop gracefully.

      {:error, reason} ->
        Logger.warning("Socket receive error: #{:inet.format_error(reason)}. Closing.")
        :ok # End the loop.
    end
  end

  defp process_buffer(socket, handler, <<>>), do: frame_loop(socket, handler, <<>>)

  defp process_buffer(socket, handler, buffer) do
    # SUGGESTION: Changed to :debug to avoid flooding production logs.
    Logger.debug("Processing buffer with handler: #{inspect(handler)}")

    case handler.frame(buffer) do
      {:ok, frame, rest} ->
        handler.handle_data(frame, socket)
        # Immediately try to process the rest of the buffer.
        process_buffer(socket, handler, rest)

      {:more, _} ->
        # The buffer contains an incomplete frame, wait for more data.
        frame_loop(socket, handler, buffer)

      {:error, reason} ->
        # SUGGESTION: On a framing error, close the connection as it's likely corrupt.
        Logger.error("Framing error, closing connection. Reason: #{inspect(reason)}")
        :ok # End the loop, which will trigger the `after` clause to close the socket.
    end
  end
end