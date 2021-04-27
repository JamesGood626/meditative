defmodule Utils do
  import Cat
  def remove_last(xs) do
    len = xs |> length
    xs |> Enum.take(len - 1)
  end

  def safe_get_map_keys(m), do: m |> Cat.maybe |> Cat.fmap(fn x -> Map.keys(x) end) |> Cat.unwrap


  def safe_list(nil), do: []
  def safe_list(xs), do: xs

  def to_list(nil), do: []
  def to_list(xs) when is_list(xs), do: xs
  def to_list(x), do: [x]

  def to_map(xs) do
    xs
    |> maybe
    ~>> fn x ->
          Enum.reduce(x, %{}, fn ({state_name, s}, acc) ->
            acc |> Map.put(state_name, s)
          end)
        end
    |> Cat.unwrap
  end
end
