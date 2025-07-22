defmodule GpsServer.Protocols.Teltonika.CRC16 do
  @moduledoc """
  Calculates CRC-16/IBM for Teltonika packets.
  Polynomial: 0xA001 (reversed representation of 0x8005)
  """
  import Bitwise

  @polynomial 0xA001

  def crc(data) when is_binary(data) do
    for <<byte <- data>>, reduce: 0 do
      acc -> calculate_byte(byte, acc)
    end
  end

  defp calculate_byte(byte, crc) do
    # XOR the byte into the CRC
    crc = bxor(crc, byte)
    # Loop 8 times for each bit
    calculate_bits(crc, 8)
  end

  defp calculate_bits(crc, 0), do: crc
  defp calculate_bits(crc, count) do
    new_crc =
      if (crc &&& 0x0001) > 0 do
        # If the LSB is 1, right-shift and XOR with the polynomial
        bxor(bsr(crc, 1), @polynomial)
      else
        # Otherwise, just right-shift
        bsr(crc, 1)
      end
    calculate_bits(new_crc, count - 1)
  end
end
