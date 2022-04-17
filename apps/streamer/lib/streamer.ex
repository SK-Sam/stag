defmodule Streamer do
  @moduledoc """
  Documentation for `Streamer`.
  """

  def start_streaming(symbol) do
    Streamer.Binance.start_link(symbol)
  end

  @doc """
  Hello world.

  ## Examples

      iex> Streamer.hello()
      :world

  """
  def hello do
    :world
  end
end
