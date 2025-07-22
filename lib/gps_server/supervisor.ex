defmodule GpsServer.Supervisor do
  @moduledoc """
  The top-level supervisor for the GpsServer application.
  It receives the listener configuration as an argument and starts a TCP server for each.
  """
  use Supervisor

  # The start_link function now accepts the listener config as an argument.
  def start_link(listeners) do
    Supervisor.start_link(__MODULE__, listeners, name: __MODULE__)
  end

  @impl true
  # The init function receives the listeners list directly as an argument.
  def init(listeners) do
    children =
      Enum.map(listeners, fn %{port: port, protocol: protocol} ->
        %{
          id: {GpsServer.TcpServer, port},
          start: {GpsServer.TcpServer, :start_link, [[port: port, protocol: protocol]]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
