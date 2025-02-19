defmodule HedgehogWeb.CryptoOrder do
  use HedgehogWeb, :live_view
  alias Hedgehog.Streamer.Binance.Worker
  alias HedgehogWeb.CryptoEnum

  require Logger

  def render(assigns) do
    ~H"""
    <div class="flex w-full flex-col border-opacity-50 px-4 sm:px-6 lg:px-8">
      <div>
        <.header class="text-center">
          Current trading Streamers
          <:subtitle>Here is a list of the cryptos watched</:subtitle>
        </.header>
        <div class="dropdown  flex justify-center">
          <div
            tabindex="0"
            role="button"
            class="btn m-1 btn-outline btn-accent disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Start Streaming
          </div>
          <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z- w-52 p-2 shadow">
            <%= for crypto <- HedgehogWeb.CryptoEnum.cryptoList do %>
              <li><a phx-click="addStreamer" phx-value-crypto={crypto}><%= crypto %></a></li>
            <% end %>
          </ul>
        </div>
      </div>
      <div class="divider">Cryptos</div>
      <div class="grid grid-cols-3 lg:grid-cols-4 gap-4">
        <%= for x <- @streamers do %>
          <div class="stats">
            <div class="stat">
              <div class="stat-figure text-primary" phx-click="deleteStreamer" phx-value-crypto={x}>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  class="inline-block h-10 w-10 stroke-current"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M0 8L3.07945 4.30466C4.29638 2.84434 6.09909 2 8 2C9.90091 2 11.7036 2.84434 12.9206 4.30466L16 8L12.9206 11.6953C11.7036 13.1557 9.90091 14 8 14C6.09909 14 4.29638 13.1557 3.07945 11.6953L0 8ZM8 11C9.65685 11 11 9.65685 11 8C11 6.34315 9.65685 5 8 5C6.34315 5 5 6.34315 5 8C5 9.65685 6.34315 11 8 11Z"
                  >
                  </path>
                </svg>
              </div>
              <div class="stat-title">Streamer</div>
              <div class="stat-value text-accent"><%= x %></div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(_, _, socket) do
    {:ok, streamers} = Worker.get_all_streamers()

    {:ok, assign(socket, streamers: streamers)}
  end

  def handle_event("deleteStreamer", %{"crypto" => crypto}, socket) do
    Hedgehog.Streamer.Binance.stop_streaming("#{crypto}")
    Logger.info("#{crypto} stream has been stopped")

    {:ok, updated_streamers} = Worker.get_all_streamers()
    socket = assign(socket, streamers: updated_streamers)

    {:noreply, socket}
  end

  def handle_event("addStreamer", %{"crypto" => crypto}, socket) do
    Hedgehog.Streamer.Binance.start_streaming("#{crypto}")
    Logger.info("#{crypto} stream has been started")

    Hedgehog.Data.Aggregator.aggregate_ohlcs("#{crypto}")
    Logger.info("#{crypto} collector has been started")

    {:ok, updated_streamers} = Worker.get_all_streamers()
    socket = assign(socket, streamers: updated_streamers)

    {:noreply, socket}
  end
end
