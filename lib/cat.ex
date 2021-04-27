defmodule Cat do
  def id(x), do: x

  @doc """
  ~>> is the monadic bind operator

  All other possible infix operators for creating defining your own operations:
  \\, <-, |, ~>>, <<~, ~>, <~, <~>, <|>, <<<, >>>, |||, &&&, and ^^^.

  Would probably use <~> for applicative functor <*>
  """
  def :none ~>> _, do: :none
  def {:some, val} ~>> func, do: func.(val) |> maybe

  @doc """
  The Applicative Machinery with the Maybe Monad
  is giving you a simple way of programming with things that can fail.
  pure (+) <*> Just 1 <*> Just 2
  => Just 3
  pure (+) <*> Just 1 <*> Nothing
  => Nothing

  and with elixir
  (&+/2) |> maybe <~> {:some, 1} <~> {:some, 2}
  => {:some, 3}
  (&+/2) |> maybe <~> {:some, 1} <~> :nothing
  => :nothing
  """
  def {:some, func} <~> {:some, val}, do: func.(val) |> maybe
  def _ <~> :nothing, do: :nothing

  def trace(x, msg) do
    IO.puts(msg)
    IO.inspect(x)
  end

  def maybe(nil), do: :none
  def maybe(x), do: {:some, x}

  def unwrap(:none), do: nil
  def unwrap({:some, val}), do: val

  def unwrap({:left, _}), do: nil
  def unwrap({:right, val}), do: val

   # NOTE: Not necessarily a category theory function... but I needed it for returning
  #       the acc value in the reduce inside of parallel_state_transition
  def unwrap_with_default(:none, default), do: default
  def unwrap_with_default({:some, val}, _), do: val

  def fmap(:none, _), do: :none
  def fmap({:some, val}, func), do: func.(val) |> maybe

  def rights(xs), do: xs |> Enum.filter(fn {:some, val} -> true
                                           :none -> false end)

  def to_either(nil, msg), do: {:left, msg}
  def to_either(val, _msg), do: {:right, val}

  def either({:left, msg}, l, _), do: {:left, l.(msg)}
  def either({:right, val}, _, r), do: {:right, r.(val)}
end
