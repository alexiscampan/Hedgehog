defmodule Hedgehog.Strategy.Naive do
  @moduledoc """
  Documentation for `Naive`.
  """

  alias Hedgehog.Strategy.Naive.DynamicTraderSupervisor
  alias Hedgehog.Strategy.Naive.Trader
  alias HedgehogWeb.CryptoEnum

  def start_trading(symbol) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.start_worker()
  end

  def stop_trading(symbol) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.stop_worker()
  end

  def shutdown_trading(symbol) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.shutdown_worker()
  end

  def get_positions(symbol) do
    symbol
    |> String.upcase()
    |> Trader.get_positions()
  end

  # def get_all_positions() do
  #   CryptoEnum.cryptoList()
  #   |> Enum.map(fn symbol ->
  #     case get_positions(symbol) do
  #       {:ok, positions} -> positions
  #       {:error, reason} ->
  #         IO.puts("Error fetching positions for #{symbol}: #{reason}")
  #     end
  #   end)
  # end
end
