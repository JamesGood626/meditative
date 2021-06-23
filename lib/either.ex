defmodule Either do
  defmodule Right do
    defstruct [:val]
  end

  defmodule Left do
    defstruct [:val]
  end

  @doc """
  iex> Either.right(100)
  %Either.Right{val: 100}
  """
  def right(x), do: %Right{val: x}
  @doc """
  iex> Either.left(100)
  %Either.Left{val: 100}
  """
  def left(x), do: %Left{val: x}

  @doc """
  iex> rv = Either.right(100)
  iex> Either.either(fn x -> 10 * x end, fn x -> 2 * x end, rv)
  200

  iex> lv = Either.left(200)
  iex> Either.either(fn x -> 10 * x end, fn x -> 2 * x end, lv)
  2000
  """
  def either(l, _, %Left{val: x}), do: l.(x)
  def either(_, r, %Right{val: x}), do: r.(x)
end
