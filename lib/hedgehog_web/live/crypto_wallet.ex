defmodule HedgehogWeb.CryptoWallet do
  use HedgehogWeb, :live_view
  alias Hedgehog.Streamer.Binance.Worker
  alias HedgehogWeb.CryptoEnum

  require Logger

  def render(assigns) do
    ~H"""
    <div class="flex w-full flex-col border-opacity-50 px-4 sm:px-6 lg:px-8 pb-4">
      <.header class="text-center">
        Current trading Positions
        <:subtitle>
          <.modal id="place-order">
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 place-items-center gap-y-8">
              <%= for crypto <- HedgehogWeb.CryptoEnum.cryptoList do %>
                <div class="indicator">
                  <div class="indicator-item indicator-bottom">
                    <button class="btn btn-accent" phx-click="startTrading" phx-value-crypto={crypto}>
                      Trade
                    </button>
                  </div>
                  <div class="card border w-[100%] ">
                    <div class="card-body">
                      <h2 class="card-title"><%= crypto %></h2>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </.modal>

          <button class="btn btn-outline btn-accent" phx-click={show_modal("place-order")}>
            Start Trading
          </button>
        </:subtitle>
        <%!-- <.icon name="wifi" class="ml-1 w-3 h-3 animate-spin" /> --%>
      </.header>
    </div>

    <div class="flex w-full items-center justify-center">
      <div class="artboard phone-3 rounded-lg border border-gray-300 shadow-md flex flex-col">
        <div class="text-center p-4">
          <h1 class="text-xl">Wallet Balances</h1>
        </div>
        <div class="overflow-x-auto w-full space-y-3">
          <%= for balance <- @balances do %>
            <ul class="menu menu-horizontal bg-base-200 rounded-box  w-[97%] flex justify-center mx-auto">
              <li>
                <a>
                  <img src={icon_url(balance["asset"])} />
                  <%= balance["asset"] %>
                </a>
              </li>
              <li class="items-center justify-center">
                <a>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <%= balance["free"] |> Decimal.round(2) %>
                  <span class="badge badge-sm badge-warning">FREE</span>
                </a>
              </li>
              <li class="items-center justify-center">
                <a>
                  <%= balance["locked"] |> Decimal.round(2) %>
                  <span class="badge badge-sm badge-error">LOCKED</span>
                </a>
              </li>
            </ul>
          <% end %>
        </div>
      </div>
      <div class="divider divider-horizontal divider-accent"></div>
      <div class="artboard phone-3 rounded-lg  flex items-center justify-center shadow-md">
        <div class="carousel carousel-vertical rounded-box w-full h-full">
          <%= if Enum.empty?(@positions) do %>
            <div class="text-center  py-4">
              <p>No positions for now</p>
            </div>
          <% else %>
            <%= for position <- @positions do %>
              <div class="carousel-item h-full bg-[url('https://img.freepik.com/free-vector/gradient-particle-wave-background_23-2150518071.jpg')] bg-cover bg-no-repeat">
                <div class="card rounded-box h-50 shadow-xl w-full grid place-items-center lg:border-r">
                  <div class="card-body text-center">
                    <h1 class="card-title text-white text-4xl">
                      <%= position.symbol %>
                      <div class="badge badge-accent"><%= position.buy_order.side %></div>
                    </h1>
                    <h2 class="text-xl text-white">Price: <%= position.buy_order.price %></h2>
                    <div class="card-actions justify-end gap-8">
                      <div class="badge  border-white-500 badge-outline text-lg px-4 py-2 text-white">
                        <%= position.buy_order.orig_qty |> Decimal.round(2) %>
                        <img src={icon_url(String.replace(position.symbol, "USDC", ""))} />
                      </div>
                      <div
                        class="badge badge-outline text-lg px-4 py-2 border-red-500 text-red-500 hover:text-white"
                        phx-click="stopTrading"
                        phx-value-crypto={position.symbol}
                      >
                        stop
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
          <%!-- <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1559703248-dcaaec9fab78.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1565098772267-60af42b81ef2.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1572635148818-ef6fd45eb394.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1494253109108-2e30c049369b.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1550258987-190a2d41a8ba.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1559181567-c3190ca9959b.webp" />
        </div>
        <div class="carousel-item h-full">
          <img src="https://img.daisyui.com/images/stock/photo-1601004890684-d8cbf643f5f2.webp" />
        </div> --%>
        </div>
      </div>
    </div>
    """
  end

  def mount(_, _, socket) do
    # Positions trigger
    positions =
      Enum.flat_map(CryptoEnum.cryptoList(), fn symbol ->
        case Hedgehog.Strategy.Naive.get_positions(symbol) do
          [%Hedgehog.Strategy.Naive.Formula.Position{} | _] = positionsL ->
            positionsL

          {:error, reason} ->
            IO.puts("Error fetching positions for #{symbol}: #{reason}")
            []
        end
      end)

    socket = assign(socket, positions: positions)

    # Balance trigger
    case Hedgehog.Strategy.Naive.Formula.get_wallet_balance() do
      {:ok, balances} ->
        case balances do
          nil ->
            IO.puts("Error: balances is nil")
            {:ok, assign(socket, balances: [], error: :balances_nil)}

          _ ->
            {:ok, assign(socket, balances: balances)}
        end

      {:error, reason} ->
        IO.puts("Error fetching account balance: #{reason}")
        {:ok, assign(socket, balances: [], error: reason)}
    end
  end

  def handle_event("stopTrading", %{"crypto" => crypto}, socket) do
    Hedgehog.Strategy.Naive.stop_trading("#{crypto}")
    Logger.info("#{crypto} position has been closed")

    positions =
      Enum.flat_map(CryptoEnum.cryptoList(), fn symbol ->
        case Hedgehog.Strategy.Naive.get_positions(symbol) do
          [%Hedgehog.Strategy.Naive.Formula.Position{} | _] = positionsL ->
            positionsL

          {:error, reason} ->
            IO.puts("Error fetching positions for #{symbol}: #{reason}")
            []
        end
      end)

    socket = assign(socket, positions: positions)

    {:noreply, socket}
  end

  def handle_event("startTrading", %{"crypto" => crypto}, socket) do
    Hedgehog.Strategy.Naive.start_trading("#{crypto}")
    Logger.info("#{crypto} position has been started")

    positions =
      Enum.flat_map(CryptoEnum.cryptoList(), fn symbol ->
        case Hedgehog.Strategy.Naive.get_positions(symbol) do
          [%Hedgehog.Strategy.Naive.Formula.Position{} | _] = positionsL ->
            positionsL

          {:error, reason} ->
            IO.puts("Error fetching positions for #{symbol}: #{reason}")
            []
        end
      end)

    socket = assign(socket, positions: positions)

    {:noreply, socket}
  end

  def icon_url(asset) do
    category = if asset == "EUR", do: "currency", else: "crypto"

    "https://raw.githubusercontent.com/VadimMalykhin/binance-icons/main/#{category}/#{String.downcase(asset)}.svg"
  end
end
