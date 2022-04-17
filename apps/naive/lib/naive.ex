defmodule Naive do
  @moduledoc """
  Documentation for `Naive`.
  """

  alias Streamer.Binance.TradeEvent

  def send_event(%TradeEvent{} = event) do
    GenServer.cast(:trader, event)
  end

  @doc """
  Hello world.

  ## Examples

      iex> Naive.hello()
      :world

  """
  def hello do
    :world
  end
end
