defmodule GpsServer.Protocols.Topflytech.Handler do
  require Logger
  alias GpsServer.Protocols.Topflytech.{Parser, Decoder}

  def frame(<<0x25, 0x25, _type, len::16, _rest::binary>> = buffer) do
    if byte_size(buffer) >= len do
      <<frame::binary-size(len), rest_of_buffer::binary>> = buffer
      {:ok, frame, rest_of_buffer}
    else
      {:more, "Need #{len} bytes, have #{byte_size(buffer)}"}
    end
  end
  def frame(<<>>), do: {:more, "Empty buffer"}
  def frame(buffer), do: {:error, {:invalid_start_bytes, buffer}}

  def handle_data(data, socket) do
    Logger.info("Processing raw Topflytech packet: #{Base.encode16(data, case: :lower)}")
    case Parser.validate(data) do
      {:ok, valid_packet} ->
        Logger.info("Parser validated packet successfully")
        handle_decoded(Decoder.decode(valid_packet), socket)

      {:error, reason} ->
        Logger.error("Parser rejected packet: #{reason |> inspect() |> IO.iodata_to_binary()}")
    end
  end

  defp handle_decoded({:ok, decoded_data = %{message_type: :login, serial_number: sn, imei: _imei, imei_bcd: imei_bcd}}, socket) do
    Logger.info("DECODED DATA [Login]:\n#{decoded_data |> inspect() |> IO.iodata_to_binary()}")
    response = <<0x25, 0x25, 0x01, 0x00, 0x0F, sn::16, imei_bcd::binary>>
    Logger.info("Login Response: #{Base.encode16(response, case: :lower)}")
    :gen_tcp.send(socket, response)
  end

  defp handle_decoded({:ok, decoded_data = %{message_type: :heartbeat, serial_number: sn, imei: _imei, imei_bcd: imei_bcd}}, socket) do
    Logger.info("DECODED DATA [Heartbeat]:\n#{decoded_data |> inspect() |> IO.iodata_to_binary()}")
    response = <<0x25, 0x25, 0x03, 0x00, 0x0F, sn::16, imei_bcd::binary>>
    Logger.info("Heartbeat Response: #{Base.encode16(response, case: :lower)}")
    :gen_tcp.send(socket, response)
  end


  defp handle_decoded({:ok, decoded_data = %{message_type: :alarm, imei: _imei, imei_bcd: imei_bcd, original_type: original_type}}, socket) do
    Logger.info("DECODED DATA [aAlarm]:\n#{decoded_data |> inspect() |> IO.iodata_to_binary()}")
    response = <<0x25, 0x25, original_type, 0x00, 0x10, 0x00, 0x10, imei_bcd::binary, 0x03>>
    Logger.info("Alarmm Response: #{Base.encode16(response, case: :lower)}")
    :gen_tcp.send(socket, response)
  end


  defp handle_decoded({:ok, decoded_data = %{message_type: _, serial_number: sn, imei: _imei, imei_bcd: imei_bcd, original_type: original_type}}, socket) do
    Logger.info("DECODED DATA [#{decoded_data.message_type}]:\n#{decoded_data |> inspect() |> IO.iodata_to_binary()}")
    response = <<0x25, 0x25, original_type, 0x00, 0x0F, sn::16, imei_bcd::binary>>
    Logger.info("Response: #{Base.encode16(response, case: :lower)}")
    :gen_tcp.send(socket, response)
  end

  defp handle_decoded({:ok, decoded_data}, _socket) do
    Logger.info("DECODED DATA [Other - #{decoded_data.message_type}]:\n#{decoded_data |> inspect() |> IO.iodata_to_binary()}")
  end

  defp handle_decoded({:error, reason}, _socket) do
    Logger.error("Failed to decode packet: #{reason |> inspect() |> IO.iodata_to_binary()}")
  end
end
