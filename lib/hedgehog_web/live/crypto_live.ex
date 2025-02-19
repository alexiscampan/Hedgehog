defmodule HedgehogWeb.CryptoLive do
  use HedgehogWeb, :live_view
  alias Hedgehog.Exchange.TradeEvent

  require Logger

  def render(assigns) do
    ~H"""
    <div class="mx-auto ">
      <.header class="text-center py-8">
        <h1 class="text-3xl font-bold text-black-800 dark:text-black mb-2">
          Current cryptos events
        </h1>
        <:subtitle>Here is the state of each crypto</:subtitle>
      </.header>

      <div class="grid grid-cols-3 lg:grid-cols-4 gap-4">
        <%= for {crypto, trade} <- Enum.sort(Map.to_list(@trade_events)) do %>
          <div>
            <div class="card bg-base-300 rounded-box h-50 shadow-xl w-full place-items-center lg:border-r">
              <div class="card-body">
                <h2 class="card-title text-primary">
                  <%= crypto %>
                  <div class="badge badge-accent">ON AIR</div>
                </h2>
                <p>Price: <%= trade.price %></p>
                <div class="card-actions justify-end">
                  <div class="badge badge-outline"><%= trade.quantity %></div>
                  <div class="badge badge-outline">
                    <%= case DateTime.from_unix(trade.event_time, :millisecond) do
                      {:ok, datetime} ->
                        Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

                      {:error, _reason} ->
                        "Invalid timestamp"
                    end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(_, _, socket) do
    Enum.each(HedgehogWeb.CryptoEnum.cryptoList(), fn crypto ->
      Phoenix.PubSub.subscribe(
        Hedgehog.PubSub,
        "TRADE_EVENTS:#{crypto}"
      )
    end)

    {:ok, assign(socket, trade_events: %{}, trades: [])}
  end

  def handle_info(%TradeEvent{} = trade_event, socket) do
    crypto = trade_event.symbol

    updated_trade_events = Map.put(socket.assigns.trade_events, crypto, trade_event)

    {:noreply,
     assign(socket,
       trade_events: updated_trade_events,
       trades: socket.assigns.trades ++ [trade_event]
     )}
  end
end
