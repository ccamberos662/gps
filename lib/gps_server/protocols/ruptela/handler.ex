defmodule GpsServer.Protocols.Ruptela.Handler do
  require Logger
  alias GpsServer.Protocols.Ruptela.{Parser, Decoder}

  def frame(<<_len::16, _rest::binary>> = buffer) do
    <<packet_len::16, _::binary>> = buffer
    total_len = 2 + packet_len
    if byte_size(buffer) >= total_len do
      <<frame::binary-size(total_len), rest_of_buffer::binary>> = buffer
      {:ok, frame, rest_of_buffer}
    else
      {:more, "Need #{total_len} bytes, have #{byte_size(buffer)}"}
    end
  end
  def frame(_), do: {:more, "Buffer too small for length field"}

  def handle_data(data, _socket) do
    Logger.info("Ruptela.Handler received data, passing to parser")
    case Parser.validate(data) do
      {:ok, valid_packet} ->
        Logger.info("Parser validated packet successfully")
        Decoder.decode(valid_packet)

      {:error, reason} ->
        Logger.error("Parser rejected packet: #{reason |> inspect() |> IO.iodata_to_binary()}")
    end
  end
end
