defmodule GpsServer.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do


    # Delay module logging to ensure all modules are loaded
    Task.start(fn ->
      :timer.sleep(2000)
      Logger.info("Compiled modules: #{inspect(:code.all_loaded() |> Enum.map(fn {mod, _} -> mod end) |> Enum.filter(fn mod -> to_string(mod) |> String.starts_with?("GpsServer.") end))}")
    end)

    # UPDATED: Read the listener configuration from the application environment.
    listeners = Application.get_env(:gps_server, :listeners, [])

    # Pass the configuration as an argument to the supervisor.
    children = [
      {GpsServer.Supervisor, listeners}
    ]

    opts = [strategy: :one_for_one, name: GpsServer.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end