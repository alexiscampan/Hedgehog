defmodule Hedgehog.Streamer.Binance.Worker do
  alias HedgehogWeb.CryptoEnum
  use WebSockex

  require Logger

  @registry :binance_streamers

  @stream_endpoint "wss://stream.binance.com:9443/ws/"

  defmodule State do
    @enforce_keys [:streamers]
    defstruct streamers: []
  end

  def start_link(symbol) do
    Logger.info(
      "Binance streamer is connecting to websocket " <>
        "stream for #{symbol} trade events"
    )

    WebSockex.start_link(
      "#{@stream_endpoint}#{String.downcase(symbol)}@trade",
      __MODULE__,
      nil,
      name: via_tuple(symbol)
    )
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> process_event(event)
      {:error, _} -> Logger.error("Unable to parse msg: #{msg}")
    end

    {:ok, state}
  end

  def call_streamer(symbol) do
    case Registry.lookup(@registry, symbol) do
      [{pid, _}] ->
        Logger.info("current streamer process for #{symbol}")

        {:ok, pid}

      _ ->
        Logger.warning("Unable to locate trader process assigned to #{symbol}")
        {:error, :unable_to_locate_streamer}
    end
  end

  def get_streamers(symbol) do
    call_streamer(symbol)
  end

  def get_all_streamers() do
    initial_streamers = CryptoEnum.cryptoList()

    streamers =
      Enum.reduce(CryptoEnum.cryptoList(), initial_streamers, fn crypto, acc_streamers ->
        case Registry.lookup(@registry, crypto) do
          [{pid, _}] ->
            Logger.info("current streamer process for #{crypto}")
            # Ne rien changer, on garde crypto dans la liste
            acc_streamers

          _ ->
            Logger.warning("Unable to locate trader process assigned to #{crypto}")
            # Supprimer crypto de la liste
            new_streamers = List.delete(acc_streamers, crypto)
            # Retourner la nouvelle liste
            new_streamers
        end
      end)

    {:ok, streamers}
  end

  defp process_event(%{"e" => "trade"} = event) do
    trade_event = %Hedgehog.Exchange.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => event["p"],
      :quantity => event["q"],
      :buyer_order_id => event["b"],
      :seller_order_id => event["a"],
      :trade_time => event["T"],
      :buyer_market_maker => event["m"]
    }

    Logger.debug(
      "Trade event received " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Hedgehog.PubSub,
      "TRADE_EVENTS:#{trade_event.symbol}",
      trade_event
    )
  end

  def get_event(%{"e" => "trade"} = event) do
    trade_event = %Hedgehog.Exchange.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => event["p"],
      :quantity => event["q"],
      :buyer_order_id => event["b"],
      :seller_order_id => event["a"],
      :trade_time => event["T"],
      :buyer_market_maker => event["m"]
    }

    {:ok, trade_event}
  end

  defp via_tuple(symbol) do
    {:via, Registry, {@registry, symbol}}
  end
end
