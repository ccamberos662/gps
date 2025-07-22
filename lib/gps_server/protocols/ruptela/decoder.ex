defmodule GpsServer.Protocols.Ruptela.Decoder do
  require Logger

  def decode(packet) do
    Logger.info("Decoding packet...")
    <<_len::16, imei_len::8, imei::binary-size(imei_len), _rest::binary>> = packet
    decoded_data = %{
      protocol: :ruptela,
      imei: imei,
      payload_raw: packet,
      received_at: DateTime.utc_now()
    }

    Logger.info("DECODED DATA: #{decoded_data |> inspect() |> IO.iodata_to_binary()}")
    {:ok, decoded_data}
  end
end
