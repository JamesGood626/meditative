defmodule State do
  @moduledoc """
  :on will be a Transition struct.

  %State{
    ...,
    parallel_states: %{
          "parallel_state_names" => ["#meditative.p.region1", "#meditative.p.region2"], <- these will be the initial parallel state whenever #meditative.p is entered.
                                                                                          And it is necessary that #meditative.p be transitioned to directly from any
                                                                                          other non-parallel state in order to enter it.
          "states" => %{ ... }
    }
  }
  """

  defstruct [:name, :on, :on_entry, :on_exit, :type, :initial_state, :parallel_states, :invoke]

  def new(%{
    "name" => name,
    "on" => on,
    "initial_state" => initial_state,
    "on_entry" => on_entry,
    "on_exit" => on_exit,
    "type" => type
  } = rest) do
    %__MODULE__{
      name: name,
      on: on,
      initial_state: initial_state,
      on_entry: on_entry,
      on_exit: on_exit,
      type: type, # TODO: add the fetching of type from the statechart on interpretation (for indicating a final state)
      parallel_states: rest |> Map.get("parallel_states"),
      invoke: rest |> Map.get("invoke")
    }
  end
end
