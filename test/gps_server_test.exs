defmodule GpsServerTest do
  use ExUnit.Case
  doctest GpsServer

  test "greets the world" do
    assert GpsServer.hello() == :world
  end
end
