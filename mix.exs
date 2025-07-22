defmodule GpsServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :gps_server,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GpsServer.Application, []}
    ]
  end

  defp deps do
    [
      # No external dependencies needed for this version
    ]
  end
end
