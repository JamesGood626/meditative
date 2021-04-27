defmodule Meditative do
  @moduledoc """
  Documentation for `Meditative`.
  """
  defdelegate interpret(statechart), to: Machine
  defdelegate interpret(statechart, opts), to: Machine
  defdelegate persist(statechart), to: Machine
  defdelegate hydrate(statechart, opts, persisted_state), to: Machine
  defdelegate transition(machine, event), to: Machine
end
