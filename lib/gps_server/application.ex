defmodule GpsServer.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Purge and delete all Teltonika modules
    for module <- [
      GpsServer.Protocols.Teltonika.Handler,
      GpsServer.Protocols.Teltonika.Parser,
      GpsServer.Protocols.Teltonika.Decoder,
      GpsServer.Protocols.Teltonika.CRC16
    ] do
      :code.purge(module)
      :code.delete(module)
    end
    Logger.info("Application compiled with version 1.7.24")
    Logger.info("Logger configuration: #{inspect(Application.get_all_env(:logger))}")
    # Delay module logging to ensure all modules are loaded
    Task.start(fn ->
      :timer.sleep(2000)
      Logger.info("Compiled modules: #{inspect(:code.all_loaded() |> Enum.map(fn {mod, _} -> mod end) |> Enum.filter(fn mod -> to_string(mod) |> String.starts_with?("GpsServer.") end))}")
    end)
    # The listener configuration is hardcoded here to ensure it's always available at startup.
    listeners = [
      %{port: 5027, protocol: :meitrack},
      %{port: 5000, protocol: :teltonika},
      %{port: 5024, protocol: :queclink},
      %{port: 5006, protocol: :ruptela},
      %{port: 5015, protocol: :topflytech}
    ]

    # Pass the configuration as an argument to the supervisor.
    children = [
      {GpsServer.Supervisor, listeners}
    ]

    opts = [strategy: :one_for_one, name: GpsServer.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
