# Meditative

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `meditative` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:meditative, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/meditative](https://hexdocs.pm/meditative).

Features currently present (TODO: include docs/example usage and test):

- Actions (for updating the context state)
- Transition Events using either a String or a map %{"type" => "TO_FOO_2", "payload" => %{"data" => ...}} ("type" is the only required key)
- Transition Events which don't trigger an update of the finite state, but instead allow you to execute Actions which may update context state.
- onEntry/onExit
- Guards
- Conditional Transitions
- Nested States
- Parallel States
- Transient Transitions denoted by "" (stored on the :on map value), for events that execute as soon as that state is entered into.

Features yet to be added:

- Conditional Actions
- Invoke
- History States

Other keys to add on the options (second argument to Machine.interpret/2) along with actions and guards are:

- activities
- delays
- services
- updater
