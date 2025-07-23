defmodule CustomLoggerFormatter do
  def format(level, message, timestamp, metadata) do
    safe_message =
      case IO.iodata_to_binary(message) do
        bin when is_binary(bin) -> bin
        _ -> inspect(message)
      end

    safe_metadata =
      metadata
      |> Enum.map(fn {k, v} ->
        try do
          "#{k}=#{IO.iodata_to_binary(inspect(v))}"
        rescue
          _ -> "#{k}=[unformattable]"
        end
      end)
      |> Enum.join(" ")

    "#{format_timestamp(timestamp)} #{safe_metadata}[#{level}] #{safe_message}\n"
  rescue
    e ->
      "Formatter error: #{inspect(e)}\n"
  end

  defp format_timestamp({date, {hour, min, sec, _}}) do
    {year, month, day} = date
    "#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(min)}:#{pad(sec)}"
  end

  defp pad(n), do: String.pad_leading(to_string(n), 2, "0")
end

import Config

config :logger, :console,
       format: {CustomLoggerFormatter, :format},
       level: :info,
       metadata: [:port, :protocol, :peer]

config :logger, :file,
       path: "gps_server.log",
       format: {CustomLoggerFormatter, :format},
       level: :info,
       metadata: [:port, :protocol, :peer]

# NEW: Listener configuration is now defined here.
config :gps_server, :listeners, [
  %{port: 5027, protocol: :meitrack},
  %{port: 5000, protocol: :teltonika},
  %{port: 5024, protocol: :queclink},
  %{port: 5006, protocol: :ruptela},
  %{port: 5015, protocol: :topflytech}
]