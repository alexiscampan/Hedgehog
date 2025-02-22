defmodule Hedgehog.Strategy.Naive.Formula do
  alias Hedgehog.Exchange.TradeEvent
  alias Decimal, as: D
  alias Hedgehog.Repo
  alias Hedgehog.Strategy.Naive.Settings
  alias Binance.Rest

  require Logger

  @binance_client Application.compile_env(:hedgehog, :binance_client)

  defmodule Position do
    @enforce_keys [
      :id,
      :symbol,
      :budget,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
    defstruct [
      :id,
      :symbol,
      :budget,
      :buy_order,
      :sell_order,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
  end

  def execute(%TradeEvent{} = trade_event, positions, settings) do
    generate_decisions(positions, [], trade_event, settings)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def parse_results([]) do
    :exit
  end

  def parse_results([_ | _] = results) do
    results
    |> Enum.map(fn {:ok, new_position} -> new_position end)
    |> then(&{:ok, &1})
  end

  def generate_decisions([], generated_results, _trade_event, _settings) do
    generated_results
  end

  def generate_decisions([position | rest] = positions, generated_results, trade_event, settings) do
    current_positions = positions ++ (generated_results |> Enum.map(&elem(&1, 0)))

    case generate_decision(trade_event, position, current_positions, settings) do
      :exit ->
        generate_decisions(rest, generated_results, trade_event, settings)

      :rebuy ->
        generate_decisions(
          rest,
          [{:skip, %{position | rebuy_notified: true}}, {:rebuy, position}] ++ generated_results,
          trade_event,
          settings
        )

      decision ->
        generate_decisions(
          rest,
          [{decision, position} | generated_results],
          trade_event,
          settings
        )
    end
  end

  def generate_decision(
        %TradeEvent{price: price},
        %Position{
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        },
        _positions,
        _settings
      ) do
    price = calculate_buy_price(price, buy_down_interval, tick_size)

    Logger.info("current budget: #{budget}")
    quantity = calculate_quantity(budget, price, step_size)

    {:place_buy_order, price, quantity}
  end

  def generate_decision(
        %TradeEvent{
          buyer_order_id: order_id
        },
        %Position{
          buy_order: %Binance.Structs.OrderResponse{
            order_id: order_id,
            status: "FILLED"
          },
          sell_order: %Binance.Structs.OrderResponse{}
        },
        _positions,
        _settings
      )
      when is_number(order_id) do
    :skip
  end

  def generate_decision(
        %TradeEvent{
          buyer_order_id: order_id
        },
        %Position{
          buy_order: %Binance.Structs.OrderResponse{
            order_id: order_id
          },
          sell_order: nil
        },
        _positions,
        _settings
      )
      when is_number(order_id) do
    :fetch_buy_order
  end

  def generate_decision(
        %TradeEvent{},
        %Position{
          buy_order: %Binance.Structs.OrderResponse{
            status: "FILLED",
            price: buy_price
          },
          sell_order: nil,
          profit_interval: profit_interval,
          tick_size: tick_size
        },
        _positions,
        _settings
      ) do
    sell_price = calculate_sell_price(buy_price, profit_interval, tick_size)
    {:place_sell_order, sell_price}
  end

  def generate_decision(
        %TradeEvent{},
        %Position{
          sell_order: %Binance.Structs.OrderResponse{
            status: "FILLED"
          }
        },
        _positions,
        settings
      ) do
    if settings.status != "shutdown" do
      :finished
    else
      :exit
    end
  end

  def generate_decision(
        %TradeEvent{
          seller_order_id: order_id
        },
        %Position{
          sell_order: %Binance.Structs.OrderResponse{
            order_id: order_id
          }
        },
        _positions,
        _settings
      ) do
    :fetch_sell_order
  end

  def generate_decision(
        %TradeEvent{
          price: current_price
        },
        %Position{
          buy_order: %Binance.Structs.OrderResponse{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        },
        positions,
        settings
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) &&
         settings.status != "shutdown" &&
         length(positions) < settings.chunks do
      :rebuy
    else
      :skip
    end
  end

  def generate_decision(%TradeEvent{}, %Position{}, _positions, _settings) do
    :skip
  end

  def calculate_sell_price(buy_price, profit_interval, tick_size) do
    fee = "1.001"
    original_price = D.mult(buy_price, fee)

    net_target_price =
      D.mult(
        original_price,
        D.add("1.0", profit_interval)
      )

    gross_target_price = D.mult(net_target_price, fee)

    D.to_string(
      D.mult(
        D.div_int(gross_target_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_buy_price(current_price, buy_down_interval, tick_size) do
    # not necessarily legal price
    exact_buy_price =
      D.sub(
        current_price,
        D.mult(current_price, buy_down_interval)
      )

    D.to_string(
      D.mult(
        D.div_int(exact_buy_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_quantity(budget, price, step_size) do
    # not necessarily legal quantity
    exact_target_quantity = D.div(budget, price)

    D.to_string(
      D.mult(
        D.div_int(exact_target_quantity, step_size),
        step_size
      ),
      :normal
    )
  end

  def trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, rebuy_interval)
      )

    D.lt?(current_price, rebuy_price)
  end

  defp execute_decision(
         {:place_buy_order, price, quantity},
         %Position{
           id: id,
           symbol: symbol
         } = position,
         _settings
       ) do
    Logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a BUY order @ #{price}, quantity: #{quantity}"
    )

    {:ok, %Binance.Structs.OrderResponse{} = order} =
      @binance_client.Trade.post_order(symbol, "BUY", "LIMIT",
        price: price,
        quantity: quantity,
        timeInForce: "GTC"
      )

    :ok = broadcast_order(order)

    {:ok, %{position | buy_order: order}}
  end

  defp execute_decision(
         {:place_sell_order, sell_price},
         %Position{
           id: id,
           symbol: symbol,
           buy_order: %Binance.Structs.OrderResponse{
             orig_qty: quantity
           }
         } = position,
         _settings
       ) do
    Logger.info(
      "Position (#{symbol}/#{id}): The BUY order is now filled. " <>
        "Placing a SELL order @ #{sell_price}, quantity: #{quantity}"
    )

    {:ok, %Binance.Structs.OrderResponse{} = order} =
      @binance_client.Trade.post_order(symbol, "SELL", "LIMIT",
        price: sell_price,
        quantity: quantity,
        timeInForce: "GTC"
      )

    :ok = broadcast_order(order)

    {:ok, %{position | sell_order: order}}
  end

  defp execute_decision(
         :fetch_buy_order,
         %Position{
           id: id,
           symbol: symbol,
           buy_order:
             %Binance.Structs.OrderResponse{
               order_id: order_id,
               transact_time: timestamp
             } = buy_order
         } = position,
         _settings
       ) do
    Logger.info("Position (#{symbol}/#{id}): The BUY order is now partially filled")

    {:ok, %Binance.Structs.Order{} = current_buy_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    :ok = broadcast_order(current_buy_order)

    buy_order = %{buy_order | status: current_buy_order.status}

    {:ok, %{position | buy_order: buy_order}}
  end

  defp execute_decision(
         :finished,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)

    Logger.info("Position (#{symbol}/#{id}): Trade cycle finished")

    {:ok, new_position}
  end

  defp execute_decision(
         :fetch_sell_order,
         %Position{
           id: id,
           symbol: symbol,
           sell_order:
             %Binance.Structs.OrderResponse{
               order_id: order_id,
               transact_time: timestamp
             } = sell_order
         } = position,
         _settings
       ) do
    Logger.info("Position (#{symbol}/#{id}): The SELL order is now partially filled")

    {:ok, %Binance.Structs.Order{} = current_sell_order} =
      @binance_client.get_order(
        symbol,
        timestamp,
        order_id
      )

    :ok = broadcast_order(current_sell_order)

    sell_order = %{sell_order | status: current_sell_order.status}

    {:ok, %{position | sell_order: sell_order}}
  end

  defp execute_decision(
         :rebuy,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)

    Logger.info("Position (#{symbol}/#{id}): Rebuy triggered. Starting new position")

    {:ok, new_position}
  end

  defp execute_decision(:skip, state, _settings) do
    {:ok, state}
  end

  defp broadcast_order(%Binance.Structs.OrderResponse{} = response) do
    response
    |> convert_to_order()
    |> broadcast_order()
  end

  defp broadcast_order(%Binance.Structs.Order{} = order) do
    Phoenix.PubSub.broadcast(
      Hedgehog.PubSub,
      "ORDERS:#{order.symbol}",
      order
    )
  end

  defp convert_to_order(%Binance.Structs.OrderResponse{} = response) do
    data =
      response
      |> Map.from_struct()

    struct(Binance.Structs.Order, data)
    |> Map.merge(%{
      cummulative_quote_qty: "0.00000000",
      stop_price: "0.00000000",
      iceberg_qty: "0.00000000",
      is_working: true
    })
  end

  def fetch_symbol_settings(symbol) do
    exchange_info = @binance_client.Market.get_exchange_info()
    db_settings = Repo.get_by!(Settings, symbol: symbol)

    merge_filters_into_settings(exchange_info, db_settings, symbol)
  end

  def merge_filters_into_settings(exchange_info, db_settings, symbol) do
    symbol_filters =
      exchange_info
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == symbol))
      |> Map.get("filters")

    tick_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
      |> Map.get("tickSize")

    step_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "LOT_SIZE"))
      |> Map.get("stepSize")

    Map.merge(
      %{
        tick_size: tick_size,
        step_size: step_size
      },
      db_settings |> Map.from_struct()
    )
  end

  def generate_fresh_position(settings, id \\ :os.system_time(:millisecond)) do
    %{
      struct(Position, settings)
      | id: id,
        budget: D.div(settings.budget, settings.chunks),
        rebuy_notified: false
    }
  end

  def update_status(symbol, status)
      when is_binary(symbol) and is_binary(status) do
    Repo.get_by(Settings, symbol: symbol)
    |> Ecto.Changeset.change(%{status: status})
    |> Repo.update()
  end

  def get_wallet_balance() do
    # Create a Binance client with your API key and secret
    # Use the Spot module to access the account endpoint
    timestamp = System.system_time(:millisecond)

    case Binance.Rest.HTTPClient.signed_request_binance(
           "/api/v3/account",
           %{"timestamp" => timestamp},
           :get
         ) do
      {:ok, account_info} ->
        balances = account_info["balances"]

        filtered_balances =
          Enum.filter(balances, fn balance ->
            String.to_float(balance["free"]) != 0 or String.to_float(balance["locked"]) != 0
          end)

        {:ok, filtered_balances}

      {:error, reason} ->
        IO.puts("Error fetching account balance: #{reason}")
        {:error, reason}
    end
  end
end
