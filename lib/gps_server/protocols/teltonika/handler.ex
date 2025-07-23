defmodule GpsServer.Protocols.Teltonika.Handler do
  @moduledoc """
  Handles the two-stage Teltonika communication:
  1. IMEI: Device connects and sends its IMEI. Server replies with 0x01.
  2. Data: Device sends AVL data packets, which are parsed and acknowledged.
  """
  require Logger
  alias GpsServer.Protocols.Teltonika.{Parser, Decoder}

  # --- Constants ---
  @imei_prefix_len 2
  @data_header_len 8 # Preamble (4) + Data Length (4)
  @data_crc_len 4

  # SUGGESTION: Define protocol responses as constants for clarity.
  @ack_imei <<1>>
  @nack_data <<-1::signed-size(32)>>

  @doc """
  Frames incoming data from the buffer. It now only returns the raw binary
  frame, letting handle_data determine the packet type.
  """
  def frame(<<0, 0, 0, 0, data_len::size(32), _rest::binary>> = buffer) do
    # SUGGESTION: Removed noisy version logging from this hot path.
    total_len = @data_header_len + data_len + @data_crc_len

    if byte_size(buffer) >= total_len do
      <<frame::binary-size(total_len), rest::binary>> = buffer
      {:ok, frame, rest}
    else
      {:more, "Need #{total_len} bytes for data packet, have #{byte_size(buffer)}"}
    end
  end

  def frame(<<imei_len::size(16), _rest::binary>> = buffer) do
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

    # Accept the connection by sending back the predefined confirmation byte.
    :gen_tcp.send(socket, @ack_imei)
    Logger.info("Sent IMEI confirmation (0x01) to #{imei_str}")
  end

  # Clause for AVL data packets (starts with 4-byte zero preamble)
  def handle_data(packet, socket) do
    case Parser.validate(packet) do
      {:ok, data_field} ->
        handle_valid_data(data_field, socket)

      {:error, reason} ->
        Logger.error("Teltonika packet validation failed: #{inspect(reason)}")
    end
  end

  defp handle_valid_data(data_field, socket) do
    case Decoder.decode(data_field) do
      {:ok, %{num_records: count} = decoded_data} ->
        Logger.info("Successfully decoded #{count} AVL records.")
        Logger.debug(fn ->
          # Log full data at debug level with a safe sanitizer
          safe_records = Enum.map(decoded_data.records, &sanitize_record/1)
          "DECODED DATA DETAILS: #{inspect(%{decoded_data | records: safe_records})}"
        end)

        # Acknowledge by sending back the number of records received as a 4-byte integer
        response = <<count::size(32)>>
        :gen_tcp.send(socket, response)
        Logger.info("Sent data acknowledgement for #{count} records.")

      {:error, reason} ->
        Logger.error("Failed to decode Teltonika data field: #{inspect(reason)}")
        # Reject by sending the predefined rejection response.
        :gen_tcp.send(socket, @nack_data)
    end
  end

  # Helper to sanitize records for logging
  defp sanitize_record(record) do
    # SUGGESTION: Simplified the function by removing the redundant GPS map update.
    Map.update(record, :io, %{}, fn io ->
      Map.new(io, fn {k, v} ->
        if is_binary(v), do: {k, Base.encode16(v, case: :lower)}, else: {k, v}
      end)
    end)
  end
end