defmodule GpsServer.Protocols.Teltonika.Decoder do
  @moduledoc """
  Decodes the `Data Field` of a Teltonika packet, supporting Codec 8 and 8 Extended.
  """
  require Logger

  @codec_8 0x08
  @codec_8_ext 0x8E

  def decode(<<codec_id::8, num_records1::8, rest::binary>>) do
    avl_decoder =
      case codec_id do
        @codec_8 -> &parse_avl_record/1
        @codec_8_ext -> &parse_avl_record_ext/1
        _ -> nil
      end

    if is_function(avl_decoder) do
      # The data field ends with a final `num_records` byte that must match the first.
      <<avl_data::binary-size(byte_size(rest) - 1), num_records2::8>> = rest

      if num_records1 == num_records2 do
        {records, <<>>} = parse_records(avl_data, num_records1, [], avl_decoder)
        {:ok, %{codec: codec_id, num_records: num_records1, records: records}}
      else
        {:error, "Record count mismatch: start=#{num_records1}, end=#{num_records2}"}
      end
    else
      {:error, "Unsupported Codec ID: #{codec_id}"}
    end
  end

  # Recursively parse all records from the AVL data block
  defp parse_records(<<>>, 0, acc, _decoder), do: {Enum.reverse(acc), <<>>}
  defp parse_records(data, count, acc, decoder) when count > 0 do
    {record, rest} = decoder.(data)
    parse_records(rest, count - 1, [record | acc], decoder)
  end

  # --- AVL Record Parsers ---

  defp parse_avl_record(data) do
    <<
      timestamp::64,
      priority::8,
      # GPS Element
      lon::integer-signed-32,
      lat::integer-signed-32,
      alt::integer-signed-16,
      angle::16,
      sats::8,
      speed::16,
      # IO Element
      event_io_id::8,
      total_io::8,
      io_data::binary
    >> = data

    {io_elements, rest} = parse_io_elements(io_data, total_io, false)

    record = %{
      timestamp: DateTime.from_unix!(div(timestamp, 1000), :millisecond),
      priority: priority,
      gps: %{
        longitude: lon / 10_000_000,
        latitude: lat / 10_000_000,
        altitude: alt,
        angle: angle,
        satellites: sats,
        speed: speed
      },
      event_io_id: event_io_id,
      io: io_elements
    }

    {record, rest}
  end

  defp parse_avl_record_ext(data) do
    <<
      timestamp::64,
      priority::8,
      # GPS Element
      lon::integer-signed-32,
      lat::integer-signed-32,
      alt::integer-signed-16,
      angle::16,
      sats::8,
      speed::16,
      # IO Element
      event_io_id::16, # 2 bytes for extended
      total_io::16,    # 2 bytes for extended
      io_data::binary
    >> = data

    {io_elements, rest} = parse_io_elements(io_data, total_io, true)

    record = %{
      timestamp: DateTime.from_unix!(div(timestamp, 1000), :millisecond),
      priority: priority,
      gps: %{
        longitude: lon / 10_000_000,
        latitude: lat / 10_000_000,
        altitude: alt,
        angle: angle,
        satellites: sats,
        speed: speed
      },
      event_io_id: event_io_id,
      io: io_elements
    }

    {record, rest}
  end

  # --- IO Element Parsers ---

  defp parse_io_elements(data, total_io, is_extended) do
    io_id_size = if is_extended, do: 16, else: 8

    {one_byte_ios, rest1} = parse_io_group(data, io_id_size, 1)
    {two_byte_ios, rest2} = parse_io_group(rest1, io_id_size, 2)
    {four_byte_ios, rest3} = parse_io_group(rest2, io_id_size, 4)
    {eight_byte_ios, rest4} = parse_io_group(rest3, io_id_size, 8)

    {x_byte_ios, final_rest} =
      if is_extended do
        parse_x_byte_io_group(rest4, io_id_size)
      else
        {%{}, rest4}
      end

    all_ios =
      Map.merge(one_byte_ios, two_byte_ios)
      |> Map.merge(four_byte_ios)
      |> Map.merge(eight_byte_ios)
      |> Map.merge(x_byte_ios)

    if map_size(all_ios) != total_io do
      Logger.warning(
        "IO count mismatch. Header says #{total_io}, but parsed #{map_size(all_ios)}"
      )
    end

    {all_ios, final_rest}
  end

  defp parse_io_group(data, id_size, value_size) do
    count_size = if id_size == 16, do: 16, else: 8
    <<num_ios::size(count_size), rest::binary>> = data

    value_bits = value_size * 8
    id_bits = id_size

    bytes_to_read = num_ios * (div(id_bits, 8) + value_size)
    <<ios_block::binary-size(bytes_to_read), rest_after::binary>> = rest

    ios =
      for <<id::size(id_bits), value::size(value_bits) <- ios_block>>, into: %{} do
        {id, value}
      end

    {ios, rest_after}
  end

  defp parse_x_byte_io_group(data, id_size) do
    count_size = if id_size == 16, do: 16, else: 8
    <<num_ios::size(count_size), rest::binary>> = data

    id_bits = id_size

    {ios, rest_after} =
      Enum.reduce(1..num_ios, {%{}, rest}, fn _, {acc, current_binary} ->
        <<
          id::size(id_bits),
          len::8,
          value::binary-size(len),
          next_binary::binary
        >> = current_binary
        {Map.put(acc, id, value), next_binary}
      end)

    {ios, rest_after}
  end
end
