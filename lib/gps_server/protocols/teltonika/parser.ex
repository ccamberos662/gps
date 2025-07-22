defmodule GpsServer.Protocols.Teltonika.Parser do
  @moduledoc """
  Validates incoming Teltonika data packets by checking the CRC.
  """
  require Logger
  alias GpsServer.Protocols.Teltonika.CRC16

  @doc """
  Validates a full data packet (Preamble + Length + Data + CRC).
  Returns `{:ok, data_field}` or `{:error, reason}`.
  """
  def validate(<<0::32, data_len::32, data_field::binary-size(data_len), crc_from_device::32>>) do
    Logger.info("Running teltonika/parser.ex version 1.7.24")
    calculated_crc = CRC16.crc(data_field)

    if calculated_crc == crc_from_device do
      Logger.info("CRC check passed. (Device: #{crc_from_device}, Calculated: #{calculated_crc})")
      {:ok, data_field}
    else
      msg = "CRC mismatch. (Device: #{crc_from_device}, Calculated: #{calculated_crc})"
      Logger.warning(msg)
      {:error, msg}
    end
  end

  def validate(packet) do
    Logger.info("Running teltonika/parser.ex version 1.7.24")
    {:error, {:invalid_packet_structure, packet}}
  end
end
