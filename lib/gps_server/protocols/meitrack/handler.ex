defmodule GpsServer.Protocols.Meitrack.Handler do
  require Logger
  def frame(buffer), do: {:ok, buffer, ""}

  def handle_data(data, _socket) do
    Logger.info("Received data for Meitrack.Handler. TODO: Implement parsing.")
    Logger.info("Raw data: #{data |> Base.encode16(case: :lower)}")
  end
end
