defmodule Transition do
  @moduledoc """
  Transition will need to add support for actions in the future.
  """
  defstruct [:event, :from, :to, :actions, :guard]

  def new(%{
    "event" => event,
    "from" => from,
    "to" => to,
  } = x) do
    %__MODULE__{
      event: event,
      from: from,
      to: to,
      actions: Map.get(x, "actions"),
      guard: Map.get(x, "guard")
    }
  end
end
