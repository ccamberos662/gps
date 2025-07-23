defmodule GpsServer.Protocols.Teltonika.Handler do
  @moduledoc """
  Handles the two-stage Teltonika communication:
  1. IMEI: Device connects and sends its IMEI. Server replies with 0x01.
  2. Data: Device sends AVL data packets, which are parsed and acknowledged.
  """
  require Logger
  alias GpsServer.Protocols.Teltonika.{Parser, Decoder}

  @imei_prefix_len 2
  @data_header_len 8 # Preamble (4) + Data Length (4)
  @data_crc_len 4

  @doc """
  Frames incoming data from the buffer. It now only returns the raw binary
  frame, letting handle_data determine the packet type.
  """
  def frame(<<0, 0, 0, 0, data_len::size(32), _rest::binary>> = buffer) do
    #Logger.info("Running teltonika/handler.ex version 1.7.24.1")
    # This is an AVL data packet (starts with zero preamble)
    total_len = @data_header_len + data_len + @data_crc_len
    if byte_size(buffer) >= total_len do
      <<frame::binary-size(total_len), rest::binary>> = buffer
      {:ok, frame, rest}
    else
      {:more, "Need #{total_len} bytes for data packet, have #{byte_size(buffer)}"}
    end
  end

  def frame(<<imei_len::size(16), _rest::binary>> = buffer) do
    Logger.info("Running teltonika/handler.ex version 1.7.24.2")
    # This is the initial IMEI packet
    total_len = @imei_prefix_len + imei_len
    if byte_size(buffer) >= total_len do
      <<frame::binary-size(total_len), rest::binary>> = buffer
      {:ok, frame, rest}
    else
      {:more, "Need #{total_len} bytes for IMEI, have #{byte_size(buffer)}"}
    end
  end

  def frame(<<>>), do: {:more, "Empty buffer"}

  def frame(buffer) do
    Logger.info("Running teltonika/handler.ex version 1.7.24.3")
    {:error, {:unknown_packet_format, buffer}}
  end

  @doc """
  Handles a framed packet from the TCP server.
  The logic to differentiate packet types is now here.
  """
  # Clause for IMEI packets (starts with 2-byte length, no zero preamble)
  def handle_data(<<_len::16, imei::binary>>, socket) do
    imei_str = IO.iodata_to_binary(imei)
    Logger.info("Teltonika device connected with IMEI: #{imei_str}")
    # Accept the connection by sending back a single byte: 0x01
    response = <<1>>
    :gen_tcp.send(socket, response)
    Logger.info("Sent IMEI confirmation (0x01) to #{imei_str}")
  end

  # Clause for AVL data packets (starts with 4-byte zero preamble)
  def handle_data(packet, socket) do
    case Parser.validate(packet) do
      {:ok, data_field} ->
        handle_valid_data(data_field, socket)
      {:error, reason} ->
        Logger.error("Teltonika packet validation failed: #{reason |> inspect() |> IO.iodata_to_binary()}")
    end
  end

  defp handle_valid_data(data_field, socket) do
    case Decoder.decode(data_field) do
      {:ok, %{num_records: count} = decoded_data} ->
        Logger.info("Successfully decoded #{count} AVL records.4")
        # Log a summary of decoded_data instead of the full structure
        Logger.info("DECODED DATA SUMMARY: codec=#{decoded_data.codec}, num_records=#{count}, records_count=#{length(decoded_data.records)}")
        # Optionally log full data with safe encoding
        safe_records = Enum.map(decoded_data.records, &sanitize_record/1)
        Logger.info("DECODED DATA DETAILS: #{inspect(%{decoded_data | records: safe_records}, limit: 50)}")
        # Acknowledge by sending back the number of records received as a 4-byte integer
        response = <<count::size(32)>>
        :gen_tcp.send(socket, response)
        Logger.info("Sent data acknowledgement for #{count} records.")

      {:error, reason} ->
        Logger.error("Failed to decode Teltonika data field: #{inspect(reason)}")
        # Reject by sending -1
        response = <<-1::signed-size(32)>>
        :gen_tcp.send(socket, response)
    end
  end

  # Helper to sanitize records for logging
  defp sanitize_record(record) do
    record
    |> Map.update(:io, %{}, fn io ->
      Map.new(io, fn {k, v} ->
        if is_binary(v), do: {k, Base.encode16(v, case: :lower)}, else: {k, v}
      end)
    end)
    |> Map.update(:gps, %{}, fn gps -> Map.new(gps, fn {k, v} -> {k, v} end) end)
  end
end
