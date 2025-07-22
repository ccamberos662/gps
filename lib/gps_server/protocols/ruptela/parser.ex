defmodule GpsServer.Protocols.Ruptela.Parser do
  def validate(packet) when is_binary(packet) do
    if byte_size(packet) > 4 do
      {:ok, packet}
    else
      {:error, :packet_too_short}
    end
  end
end
