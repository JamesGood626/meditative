# Meditative

The MIT License (MIT)

Copyright (c) 2019 GitHub, Inc. and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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
- Invoke (Promises, Actors, etc...)
- History States

Other keys to add on the options (second argument to Machine.interpret/2) along with actions and guards are:

- activities
- delays
- services
- updater

TODO: Create an Elixir Forum post of the above notes and inquire as to whether anyone would be interested in this feature set being published as an open source library (cause I'm an open source newb).
