defmodule GpsServer.Protocols.Topflytech.Parser do
  require Logger

  def validate(packet) when is_binary(packet) do
    Logger.info("Bypassing validation for Topflytech packet as per documentation.")
    {:ok, packet}
  end

  def validate(_), do: {:error, :invalid_packet_type}
end
