defmodule Naive.Trader do
  @moduledoc """
  Trader is an abstraction which needs to know:
    - Crypto Symbol its trading with
    - Placed buy order
    - Placed sell order
    - Profit interval(net profit% to achieve in a single trade cycle)
    - Tick Size(smallest acceptable price movement up or down)
      + Ex: USD can tick up/down by $0.01
  """
  use GenServer

  require Logger

  alias Streamer.Binance.TradeEvent

  defmodule State do
    @enforce_keys [:symbol, :profit_interval, :tick_size]
    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_interval,
      :tick_size
    ]
  end

  def start_link(%{} = args) do
    GenServer.start_link(__MODULE__, args, name: :trader)
  end

  def init(%{symbol: symbol, profit_interval: profit_interval}) do
    symbol = String.upcase(symbol)

    Logger.info("Initializing new trader for #{symbol}")

    tick_size = fetch_tick_size(symbol)

    {:ok,
     %State{
       symbol: symbol,
       profit_interval: profit_interval,
       tick_size: tick_size
     }}
  end

  # Pattern match on buy_order = nil to confirm dealing with New Trader
  # in order to place a new buy order.
  def handle_cast(
        %TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    quantity = "100"

    Logger.info("Placing BUY order for #{symbol} @ #{price}, quantity: #{quantity}")

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(symbol, quantity, price, "GTC")

    {:noreply, %{state | buy_order: order}}
  end

  # Pattern match on Buyer Order existence to confirm buy order was filled.
  # Proceed with placing a sell order
  def handle_cast(
        %TradeEvent{
          buyer_order_id: order_id,
          quantity: quantity
        },
        %State{
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            order_id: order_id,
            orig_qty: quantity
          },
          profit_interval: profit_interval,
          tick_size: tick_size
        } = state
      ) do
    sell_price = calculate_sell_price(buy_price, profit_interval, tick_size)

    Logger.info(
      "Buy order filled, placing Sell order for " <>
        "#{symbol} @ #{sell_price}, quantity: #{quantity}"
    )

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_sell(symbol, quantity, sell_price, "GTC")

    {:noreply, %{state | sell_order: order}}
  end

  # Trader confirming his sell order was filled.
  def handle_cast(
        %TradeEvent{
          seller_order_id: order_id,
          quantity: quantity
        },
        %State{
          sell_order: %Binance.OrderResponse{
            order_id: order_id,
            orig_qty: quantity
          }
        } = state
      ) do
    Logger.info("Trade finished, trader will now eit")

    {:stop, :normal, state}
  end

  # Trader has an open order, and incoming event should not interrupt this trader. We ignore incoming event.
  def handle_cast(%TradeEvent{}, state) do
    {:noreply, state}
  end

  # Each symbol has a different tick and may change as time passes.
  # Fetch each time we start a process in case withdrawal is enabled.
  defp fetch_tick_size(symbol) do
    Binance.get_exchange_info()
    |> elem(1)
    |> Map.get(:symbols)
    |> Enum.find(&(&1["symbol"] == symbol))
    |> Map.get("filters")
    |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
    |> Map.get("tickSize")
  end

  defp calculate_sell_price(buy_price, profit_interval, tick_size) do
    # 0.1%
    fee = "1.001"

    # Original price = buy price + fee
    original_price = Decimal.mult(buy_price, fee)

    # Net Target Price = original price x profit interval
    net_target_price =
      Decimal.mult(
        original_price,
        Decimal.add("1.0", profit_interval)
      )

    # Gross Target Price(Charged fee for selling) = fee x net target price
    gross_target_price = Decimal.mult(net_target_price, fee)

    # Use tick size to normalize number
    Decimal.to_string(
      Decimal.mult(
        Decimal.div_int(gross_target_price, tick_size),
        tick_size
      ),
      :normal
    )
  end
end
