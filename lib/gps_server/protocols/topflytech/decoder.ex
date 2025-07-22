defmodule GpsServer.Protocols.Topflytech.Decoder do
  require Logger
  import Bitwise

  def decode(<<0x25, 0x25, message_type, _len::16, payload::binary>>) do
    Logger.info("Decoding Topflytech message type: 0x#{Integer.to_string(message_type, 16)}")
    case message_type do
      0x01 -> decode_login(payload, message_type)
      0x02 -> decode_location_v1(payload, message_type)
      0x03 -> decode_heartbeat(payload, message_type)
      0x04 -> decode_location_v1(payload, message_type, :alarm)
      0x13 -> decode_location_v2(payload, message_type, :alarm)
      0x14 -> decode_location_v2(payload, message_type, :alarm)
      0x16 -> decode_location_with_sensor(payload, message_type)
      0x18 -> decode_location_with_sensor(payload, message_type, :alarm)
      0x33 -> decode_location_v2_with_sensor(payload, message_type)
      0x34 -> decode_location_v2_with_sensor(payload, message_type, :alarm)
      _ ->
        Logger.warning("Message type 0x#{Integer.to_string(message_type, 16)} has a placeholder decoder.")
        <<sn::16, imei_bcd::binary-size(8), _rest::binary>> = payload
        imei = bcd_to_string(imei_bcd)
        {:ok, %{message_type: :"type_#{message_type}", serial_number: sn, imei: imei, imei_bcd: imei_bcd, original_type: message_type, payload: payload}}
    end
  end

  defp decode_login(<<sn::16, imei_bcd::binary-size(8), _rest::binary>>, original_type) do
    imei_string = bcd_to_string(imei_bcd)
    {:ok, %{message_type: :login, serial_number: sn, imei: imei_string, imei_bcd: imei_bcd, original_type: original_type}}
  end

  defp decode_heartbeat(<<sn::16, imei_bcd::binary-size(8), _rest::binary>>, original_type) do
    imei_string = bcd_to_string(imei_bcd)
    {:ok, %{message_type: :heartbeat, serial_number: sn, imei: imei_string, imei_bcd: imei_bcd, original_type: original_type}}
  end

  defp decode_location_v1(payload, original_type, type \\ :location) do
    try do
      <<
        sn::16,
        imei_bcd::binary-size(8),
        year_bcd::8, month_bcd::8, day_bcd::8, hour_bcd::8, min_bcd::8, sec_bcd::8,
        sats::8,
        lat::integer-32,
        lon::integer-32,
        speed::8,
        course_status::16,
        mcc::16,
        mnc::8,
        lac::16,
        cell_id::24,
        odo::32
      >> = payload

      imei = bcd_to_string(imei_bcd)
      year = bcd_byte_to_int(year_bcd)
      month = bcd_byte_to_int(month_bcd)
      day = bcd_byte_to_int(day_bcd)
      hour = bcd_byte_to_int(hour_bcd)
      min = bcd_byte_to_int(min_bcd)
      sec = bcd_byte_to_int(sec_bcd)

      with {:ok, timestamp} <- create_timestamp(year, month, day, hour, min, sec) do
        {:ok, %{
          message_type: type,
          serial_number: sn,
          imei: imei,
          imei_bcd: imei_bcd,
          original_type: original_type,
          timestamp: timestamp,
          gps: %{
            satellites: sats,
            latitude: lat / 1_000_000,
            longitude: lon / 1_000_000,
            speed_kmh: speed,
            course: band(course_status, 0x03FF),
            status: gps_status(course_status)
          },
          network: %{mcc: mcc, mnc: mnc, lac: lac, cell_id: cell_id},
          odometer_km: odo / 1000
        }}
      else
        err -> err
      end
    rescue
      e ->
        Logger.error("Failed to parse 0x02/0x04 packet. Error: #{inspect(e) |> IO.iodata_to_binary()}. Payload: #{inspect(payload) |> IO.iodata_to_binary()}")
        {:error, :invalid_location_v1_format}
    end
  end

  defp decode_location_v2(payload, original_type, type) do
    try do
      <<
        _sn::16,
        _imei_bcd::binary-size(8),
        _rest::binary
      >> = payload
      decode_location_v2_with_sensor(payload, original_type, type)
    rescue
      e ->
        Logger.error("Failed to parse 0x13/0x14 packet. Error: #{inspect(e) |> IO.iodata_to_binary()}. Payload: #{inspect(payload) |> IO.iodata_to_binary()}")
        {:error, :invalid_location_v2_format}
    end
  end

  defp decode_location_with_sensor(payload, original_type, type \\ :location_with_sensor) do
    v1_size = 51
    <<v1_payload::binary-size(v1_size), sensor_data::binary>> = payload

    case decode_location_v1(v1_payload, original_type, type) do
      {:ok, decoded} -> {:ok, Map.put(decoded, :sensor_data, sensor_data)}
      err -> err
    end
  end

  defp decode_location_v2_with_sensor(payload, original_type, type \\ :location_v2_with_sensor) do
    try do
      <<
        sn::16,
        imei_bcd::binary-size(8),
        acc_on_interval::16,
        acc_off_interval::16,
        angle_comp::8,
        dist_comp::16,
        speed_alarm::16,
        gps_status_byte::8,
        gsensor_status_byte::8,
        other_status_byte::8,
        heartbeat_interval::8,
        relay_status_byte::8,
        drag_alarm_setting::16,
        dig_in_status_byte::16,
        dig_out_status_byte::8,
        _reserved1::8,
        analog1::16,
        analog2::16,
        analog3::16,
        _distance_since_last::32,
        alarm_code::8,
        gps_state_byte::8,
        mileage::32,
        battery_percent::8,
        year_bcd::8, month_bcd::8, day_bcd::8, hour_bcd::8, min_bcd::8, sec_bcd::8,
        height::float-32,
        lon::float-32,
        lat::float-32,
        speed_kmh::16,
        direction::16,
        internal_voltage::16,
        external_voltage::16,
        rpm::16,
        smart_upload_byte::8,
        low_power_byte::16,
        device_temp::8,
        sensor_data::binary
      >> = payload

      imei = bcd_to_string(imei_bcd)
      year = bcd_byte_to_int(year_bcd)
      month = bcd_byte_to_int(month_bcd)
      day = bcd_byte_to_int(day_bcd)
      hour = bcd_byte_to_int(hour_bcd)
      min = bcd_byte_to_int(min_bcd)
      sec = bcd_byte_to_int(sec_bcd)

      with {:ok, timestamp} <- create_timestamp(year, month, day, hour, min, sec) do
        {:ok, %{
          message_type: type,
          serial_number: sn,
          imei: imei,
          imei_bcd: imei_bcd,
          original_type: original_type,
          config: %{
            acc_on_interval: acc_on_interval,
            acc_off_interval: acc_off_interval,
            angle_compensation: angle_comp,
            distance_compensation: dist_comp,
            speed_alarm: speed_alarm,
            heartbeat_interval_min: heartbeat_interval,
            drag_alarm_setting: drag_alarm_setting
          },
          status: %{
            gps_data: parse_gps_data_status(gps_status_byte),
            gsensor_manager: parse_gsensor_status(gsensor_status_byte),
            other: parse_other_status(other_status_byte),
            relay: parse_relay_status(relay_status_byte),
            digital_inputs: parse_digital_inputs(dig_in_status_byte),
            digital_outputs: parse_digital_outputs(dig_out_status_byte),
            gps_state: parse_gps_state(gps_state_byte),
            smart_upload: smart_upload_byte,
            low_power_rechargeable: low_power_byte == 0xFFFF
          },
          analog_inputs: %{
            "1": analog1 / 100.0,
            "2": analog2 / 100.0,
            "3": analog3 / 100.0
          },
          alarm_code: alarm_code,
          mileage_m: mileage,
          battery_percent: battery_percent,
          timestamp: timestamp,
          gps: %{
            height: height,
            longitude: lon,
            latitude: lat,
            speed_kmh: speed_kmh / 10.0,
            direction: direction
          },
          power: %{
            internal_voltage: internal_voltage / 10.0,
            external_voltage: external_voltage / 10.0
          },
          rpm: rpm,
          device_temp_c: device_temp,
          sensor_data: sensor_data
        }}
      else
        {:error, reason} -> {:error, reason}
      end
    rescue
      e ->
        Logger.error("Failed to parse V2 sensor packet. Error: #{inspect(e) |> IO.iodata_to_binary()}. Payload: #{inspect(payload) |> IO.iodata_to_binary()}")
        {:error, :invalid_location_v2_with_sensor_format}
    end
  end

  defp bcd_to_string(bcd_binary) do
    for <<nibble::4 <- bcd_binary>>, into: "", do: Integer.to_string(nibble)
  end

  defp bcd_byte_to_int(bcd_byte) do
    (bsr(bcd_byte, 4)) * 10 + (band(bcd_byte, 15))
  end

  defp create_timestamp(y, m, d, h, min, s) do
    case {Date.new(2000 + y, m, d), Time.new(h, min, s, 0)} do
      {{:ok, date}, {:ok, time}} ->
        {:ok, DateTime.new!(date, time, "Etc/UTC")}
      _ ->
        {:error, {:invalid_timestamp, [y, m, d, h, min, s]}}
    end
  end

  defp gps_status(cs) do
    %{real_time: band(cs, 4096) == 0, fixed: band(cs, 8192) != 0}
  end

  defp parse_gps_data_status(byte) do
    %{
      history_data: band(byte, 64) != 0,
      gnss_data: band(byte, 32) != 0,
      gnss_working: band(byte, 16) != 0,
      satellite_number: band(byte, 15)
    }
  end

  defp parse_gsensor_status(byte) do
    %{
      gsensor: band(byte, 128) != 0,
      admin_manager_1_open: band(byte, 32) != 0,
      admin_manager_2_open: band(byte, 16) != 0,
      admin_manager_3_open: band(byte, 8) != 0,
      admin_manager_4_open: band(byte, 4) != 0
    }
  end

  defp parse_other_status(byte) do
    %{
      lock_sim: band(byte, 128) != 0,
      lock_tracker: band(byte, 64) != 0,
      antithefted_status: band(byte, 32) != 0,
      vibration_level: band(byte, 31)
    }
  end

  defp parse_relay_status(byte) do
    %{
      relay_status: band(byte, 128) != 0,
      relay_mode: band(byte, 96) |> bsr(5),
      sms_language: band(byte, 31)
    }
  end

  defp parse_digital_inputs(byte) do
    %{
      external_power_connected: band(byte, 32768) != 0,
      acc_on: band(byte, 16384) != 0,
      input_0: band(byte, 8192) != 0,
      input_1: band(byte, 4096) != 0,
      input_2: band(byte, 2048) != 0,
      input_3: band(byte, 1024) != 0,
      input_4: band(byte, 512) != 0,
      input_5: band(byte, 256) != 0,
      accdet: band(byte, 4) != 0,
      fms_data: band(byte, 2) != 0,
      mileage_source_gps: band(byte, 1) != 0
    }
  end

  defp parse_digital_outputs(byte) do
    %{
      vout_5v: band(byte, 128) != 0,
      vout_12v: band(byte, 64) != 0,
      vout_open: band(byte, 32) != 0,
      output_1: band(byte, 8) != 0,
      output_2: band(byte, 4) != 0,
      output_3: band(byte, 2) != 0
    }
  end

  defp parse_gps_state(byte) do
    %{
      gps_glonass: band(byte, 128) != 0,
      sms_alarm_open: band(byte, 64) != 0,
      digital_2_alarm_open: band(byte, 32) != 0,
      jammer_detection_status: band(byte, 3)
    }
  end
end
