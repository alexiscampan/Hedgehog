defmodule Hedgehog.Streamer.Binance do
  @moduledoc """
  Documentation for `Streamer`.
  """
  alias Hedgehog.Streamer.Binance.DynamicStreamerSupervisor
  alias Hedgehog.Streamer.Binance.Worker

  def start_streaming(symbol) do
    symbol
    |> String.upcase()
    |> DynamicStreamerSupervisor.start_worker()
  end

  def stop_streaming(symbol) do
    symbol
    |> String.upcase()
    |> DynamicStreamerSupervisor.stop_worker()
  end

  def get_streamers(symbol) do
    symbol
    |> String.upcase()
    |> Worker.get_streamers()
  end
end
