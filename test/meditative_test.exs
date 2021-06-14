defmodule MeditativeTest do
  use ExUnit.Case
  doctest Meditative
  alias Machine
  alias State
  alias Transition

  # IMMEDIATE TODO:
  # Need to support global events... (which will be executed no matter what the current state is)
  # Reference XState


  setup_all do
    actions = %{
      # If the action function returns an Assign struct, then update
      # the context with the map stored on the Assign under the :next_context key.
      "increment" => fn (context, event) ->
                      count = context |> Map.get("count")
                      %{"count" => count + 1}
                     end
    }

    guards = %{
      "retries_not_exceeded" => fn context -> Map.get(context, "count") < 3 end
    }
    statechart = %{
      "id" => "meditative",
      "initial_state" => "p",
      "context" => %{
        "count" => 0,
        "name" => nil
      },
      # LATER TODO: Started working on this... so that this event can be triggered irregardless of what the current finite state is,
      #             but gonna need to save this for later.
      #             Going to require possibly writing a different implmentation of the construct_transitions function.
      # "on" => %{
        # "UPDATE" => %{
        #   "actions" => ["increment", "increment", "increment"]
        # },
      # },
      "states" => %{
        "p" => %{
          # ["#meditative.p", "#meditative.p.region1.foo1",
          #   "#meditative.p.region1.foo1.flop", "#meditative.p.region1.foo1.turn",
          #   "#meditative.p.region1.foo1.river", "#meditative.p.region1.foo2",
          #   "#meditative.p.region2", "#meditative.p.region2.bar1",
          #   "#meditative.p.region2.bar2"]
          #   iex(4)> xs |> length
          #   9
          "type" => "parallel",
          "states" => %{
            "region1" => %{
              "initial_state" => "foo1",
              "states" => %{
                "foo1" => %{
                  "on" => %{
                    "TO_FOO_2" => "foo2",
                    "GTFO" => "#meditative.first_step"
                  },
                  "states" => %{
                    "flop" => %{
                      "on" => %{
                        "END_BETTING" => "turn"
                      },
                    },
                    "turn" => %{
                      "on" => %{
                        "END_BETTING" => "river"
                      }
                    },
                    "river" => %{
                      "type" => "final"
                    }
                  }
                 },
                "foo2" => %{
                  "on" => %{
                    "TO_FOO_1" => "foo1"
                  }
                 }
              }
            },
            "region2" => %{
              "initial_state" => "bar1",
              "states" => %{
                "bar1" => %{ "type" => "final" },
                "bar2" => %{ "type" => "final" }
              }
            }
          },
        },
        "first_step" => %{
          # "on_exit" => "increment",
          "on" => %{
            "UPDATE" => %{
              "actions" => ["increment", "increment", "increment"]
            },
            "RUN" => %{
              "target" => "nested_first_step"
            },
          },
          "states" => %{
            "to_the_right" => %{
              "on" => %{
                # TODO/NOTE: I accidentally included the key "actions" on the "on" map, should
                # check for that key in my code and provide a useful error message.
                "RUN" => %{
                  "target" => "#meditative.first_step",
                  "actions" => ["increment"],
                  "guard" => "retries_not_exceeded" # String | [String]
                },
              }
            },
            "nested_first_step" => %{
              "on" => %{
                # "" => [
                #   %{
                #     "target" => "to_the_right",
                #     "guard" => "retries_not_exceeded"
                #   },
                #   "to_the_left"
                # ],
                # NOTE/TODO:
                # Nested steps can specify an absolute state value to target as the transition to state
                # "#model-creation-steps.save_model"
                # if the string doesn't start with a '#' then it's a relative path (a state at the same level)
                "SLIDE" => "to_the_right"
              },
              "initial_state" => "to_the_left",
              "states" => %{
                "to_the_left" => %{ "type" => "final" },
                "two_levels_deep_nested_step" => %{
                  "on" => %{
                    "SLIDE" => %{
                      "target" => "to_the_left",
                      "actions" => "increment"
                    }
                  }
                }
              }
            }
          }
        },
        "second_step" => %{
          "type" => "final"
        }
      }
    }

    interpreted_statechart = %Machine{
      actions: nil,
      context: %{"count" => 0, "name" => nil},
      current_state: ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"],
      guards: nil,
      id: "meditative",
      parallel_state_key: "#meditative.p",
      states: %{
        "#meditative.first_step" => %State{
          initial_state: nil,
          name: "#meditative.first_step",
          on: %{
            "RUN" => %Transition{actions: nil, event: "RUN", from: "#meditative.first_step", guard: nil, to: "#meditative.first_step.nested_first_step"},
            "UPDATE" => %Transition{actions: ["increment", "increment", "increment"], event: "UPDATE", from: "#meditative.first_step", guard: nil, to: nil}
          },
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: nil
        },
        "#meditative.first_step.nested_first_step" => %State{
          initial_state: "#meditative.first_step.nested_first_step.to_the_left",
          name: "#meditative.first_step.nested_first_step",
          on: %{
            "SLIDE" => %Transition{
              actions: nil,
              event: "SLIDE",
              from: "#meditative.first_step.nested_first_step",
              guard: nil,
              to: "#meditative.first_step.to_the_right"
              }
          },
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: nil
        },
        "#meditative.first_step.nested_first_step.to_the_left" => %State{
          initial_state: nil,
          name: "#meditative.first_step.nested_first_step.to_the_left",
          on: %{},
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: "final"
        },
        "#meditative.first_step.nested_first_step.two_levels_deep_nested_step" => %State{
          initial_state: nil,
          name: "#meditative.first_step.nested_first_step.two_levels_deep_nested_step",
          on: %{"SLIDE" => %Transition{
            actions: "increment",
            event: "SLIDE",
            from: "#meditative.first_step.nested_first_step.two_levels_deep_nested_step",
            guard: nil,
            to: "#meditative.first_step.nested_first_step.to_the_left"}
          },
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: nil
        },
        "#meditative.first_step.to_the_right" => %State{
          initial_state: nil,
          name: "#meditative.first_step.to_the_right",
          on: %{
            "RUN" => %Transition{
              actions: ["increment"],
              event: "RUN",
              from: "#meditative.first_step.to_the_right",
              guard: "retries_not_exceeded",
              to: "#meditative.first_step"
            }
          },
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: nil
        },
        "#meditative.p" => %State{
          initial_state: nil,
          name: "#meditative.p",
          on: %{},
          on_entry: nil,
          on_exit: nil,
          parallel_states: %{
            "parallel_state_names" => ["#meditative.p.region1", "#meditative.p.region2"],
            "states" => %{
              "#meditative.p" => %{"type" => "parallel"},
              "#meditative.p.region1" => %State{
                initial_state: "#meditative.p.region1.foo1",
                name: "#meditative.p.region1",
                on: %{},
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: nil
              },
              "#meditative.p.region1.foo1" => %State{
                initial_state: nil,
                name: "#meditative.p.region1.foo1",
                on: %{
                  "GTFO" => %Transition{
                    actions: nil,
                    event: "GTFO",
                    from: "#meditative.p.region1.foo1",
                    guard: nil,
                    to: "#meditative.first_step"
                  },
                  "TO_FOO_2" => %Transition{
                    actions: nil,
                    event: "TO_FOO_2",
                    from: "#meditative.p.region1.foo1",
                    guard: nil,
                    to: "#meditative.p.region1.foo2"
                    }
                  },
                  on_entry: nil,
                  on_exit: nil,
                  parallel_states: nil,
                  type: nil
              },
              "#meditative.p.region1.foo1.flop" => %State{
                initial_state: nil,
                name: "#meditative.p.region1.foo1.flop",
                on: %{
                  "END_BETTING" => %Transition{
                    actions: nil,
                    event: "END_BETTING",
                    from: "#meditative.p.region1.foo1.flop",
                    guard: nil,
                    to: "#meditative.p.region1.foo1.turn"
                  }
                },
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: nil
              },
              "#meditative.p.region1.foo1.river" => %State{
                initial_state: nil,
                name: "#meditative.p.region1.foo1.river",
                on: %{},
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: "final"
              },
              "#meditative.p.region1.foo1.turn" => %State{
                initial_state: nil,
                name: "#meditative.p.region1.foo1.turn",
                on: %{
                  "END_BETTING" => %Transition{
                    actions: nil,
                    event: "END_BETTING",
                    from: "#meditative.p.region1.foo1.turn",
                    guard: nil,
                    to: "#meditative.p.region1.foo1.river"
                  }
                },
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: nil
              },
              "#meditative.p.region1.foo2" => %State{
                initial_state: nil,
                name: "#meditative.p.region1.foo2",
                on: %{
                  "TO_FOO_1" => %Transition{
                    actions: nil,
                    event: "TO_FOO_1",
                    from: "#meditative.p.region1.foo2",
                    guard: nil,
                    to: "#meditative.p.region1.foo1"
                  }
                },
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: nil
              },
              "#meditative.p.region2" => %State{
                initial_state: "#meditative.p.region2.bar1",
                name: "#meditative.p.region2",
                on: %{},
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: nil
              },
              "#meditative.p.region2.bar1" => %State{
                initial_state: nil,
                name: "#meditative.p.region2.bar1",
                on: %{},
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: "final"
              },
              "#meditative.p.region2.bar2" => %State{
                initial_state: nil,
                name: "#meditative.p.region2.bar2",
                on: %{},
                on_entry: nil,
                on_exit: nil,
                parallel_states: nil,
                type: "final"
              }
            }
          },
          type: "parallel"
        },
        "#meditative.second_step" => %State{
          initial_state: nil,
          name: "#meditative.second_step",
          on: %{},
          on_entry: nil,
          on_exit: nil,
          parallel_states: nil,
          type: "final"
        }
      }
    }

    %{statechart: statechart, interpreted_statechart: interpreted_statechart, actions: actions, guards: guards}
  end

  test "Machine supports events for which the transition has no target finite state, but only runs actions", %{statechart: statechart, actions: actions, guards: guards} do
    machine =
      Meditative.interpret(statechart, %{"actions" => actions, "guards" => guards})
      |> Meditative.transition("GTFO")
      |> Meditative.transition("UPDATE")

    assert (machine |> Map.get(:context)) === %{"count" => 3, "name" => nil}
  end

  test "Machine.interpret/1 interprets a statechart by converting to a structure that supports statechart functionality.", %{statechart: statechart, interpreted_statechart: interpreted_statechart} do
    assert Meditative.interpret(statechart) === interpreted_statechart
  end

  test "Machine.transition/2 successfully updates the finite state of a statechart with active parallel states.", %{statechart: statechart, interpreted_statechart: interpreted_statechart, actions: actions, guards: guards} do
    machine = Meditative.interpret(statechart, %{"actions" => actions, "guards" => guards})
    state_before_transition = machine |> Map.get(:current_state)
    updated_machine = Meditative.transition(machine, %{"type" => "TO_FOO_2", "payload" => %{"data" => %{}}})
    state_after_transition = updated_machine |> Map.get(:current_state)

    assert state_before_transition === ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"]
    assert state_after_transition === ["#meditative.p.region1.foo2", "#meditative.p.region2.bar1"]
  end

  test "Machine.transition/2 successfully transitions out of an active parallel state.", %{statechart: statechart, interpreted_statechart: interpreted_statechart, actions: actions, guards: guards} do
    machine = Meditative.interpret(statechart, %{"actions" => actions, "guards" => guards})
    state_before_transition = machine |> Map.get(:current_state)
    updated_machine = Meditative.transition(machine, "GTFO")
    state_after_transition = updated_machine |> Map.get(:current_state)

    assert state_before_transition === ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"]
    assert state_after_transition === "#meditative.first_step"
  end

  test "Machine.persist/1 successfully returns a map containing 'current_state', 'context', and 'parallel_state_key' from the statechart.", %{statechart: statechart, interpreted_statechart: interpreted_statechart, actions: actions, guards: guards} do
    persisted_state = %{
      "current_state" => ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"],
      "context" => %{"count" => 0, "name" => nil},
      "parallel_state_key" => "#meditative.p"
    }

    machine = Meditative.interpret(statechart, %{"actions" => actions, "guards" => guards})
    assert Meditative.persist(machine) === persisted_state
  end

  # TODO: There are no guarantees around this, so it can be misused by the end user if they pass in incompatible persisted_state along with a statechart definition that it doesn't go with.
  # Possible simple solution to provide some kind of guarantee? -> Check that the context's of the statechart definition and the persisted_state map have all of the same keys,
  test "Machine.hydrate/3 successfully restores a statechart to its previous state, when provided.", %{statechart: statechart, interpreted_statechart: interpreted_statechart, actions: actions, guards: guards} do
    persisted_state = %{
      "current_state" => "#meditative.first_step",
      "context" => %{"count" => 2, "name" => nil},
      "parallel_state_key" => nil
    }

    machine = Meditative.hydrate(statechart, %{"actions" => actions, "guards" => guards}, persisted_state)
    assert machine |> Map.get(:current_state) === "#meditative.first_step"
    assert machine |> Map.get(:context) === %{"count" => 2, "name" => nil}
  end

  test "Machine which has a transition with an action and no transition target, may trigger a transition from within the action." do
    actions = %{
      "increment_and_transition_finite_state" => fn (context, event) ->
                      count = context |> Map.get("count")
                      {"TRANSITION_TO_B", %{"count" => count + 1}}
                     end
    }

    statechart = %{
      "id" => "meditative",
      "initial_state" => "a",
      "context" => %{
        "count" => 0
      },
      "states" => %{
        "a" => %{
          "on" => %{
            "DO_IT" => %{
              "actions" => "increment_and_transition_finite_state"
            },
            "TRANSITION_TO_B" => %{"target" => "b"}
          }
        },
        "b" => %{
          "type" => "final"
        }
      }
    }

      machine = Meditative.interpret(statechart, %{"actions" => actions, "guards" => nil})
      state_before_transition = machine |> Map.get(:current_state)
      updated_machine = Meditative.transition(machine, "DO_IT")
      state_after_transition = updated_machine |> Map.get(:current_state)

      assert state_before_transition === "#meditative.a"
      assert state_after_transition === "#meditative.b"
  end

  test "Machine runs actions first, followed by guards whenever an incoming transition event is received" do
    actions = %{
      # TODO/NOTE: This is a fucked situation... test fails if I just return %{"count" => 1} from the action function.
      "set_necessary_context_to_fulfill_transition" => fn (context, event) -> {nil, %{"count" => 1}} end,
      "set_necessary_context_to_avoid_transition" => fn (context, event) -> %{"count" => 0} end
    }

    guards = %{
      "count_is_not_zero?" => fn %{"count" => count} -> count !== 0 end
    }

    statechart = %{
      "id" => "meditative",
      "initial_state" => "a",
      "context" => %{
        "count" => 0
      },
      "states" => %{
        "a" => %{
          "on" => %{
            "DO_IT" => %{
              "target" => "b",
              "actions" => "set_necessary_context_to_fulfill_transition",
              "guards" => "count_is_not_zero?"
            },
          }
        },
        "b" => %{
          "DO_IT" => %{
            "target" => "a",
            "actions" => "set_necessary_context_to_avoid_transition",
            "guards" => "count_is_not_zero?"
          },
        }
      }
    }

    machine = Meditative.interpret(statechart, %{"actions" => actions, "guards" => nil})
    state_before_transition = machine |> Map.get(:current_state)
    updated_machine = Meditative.transition(machine, "DO_IT")
    state_after_first_transition = updated_machine |> Map.get(:current_state)
    updated_machine = Meditative.transition(updated_machine, "DO_IT")
    state_after_second_transition = updated_machine |> Map.get(:current_state)

    assert state_before_transition === "#meditative.a"
    assert state_after_first_transition === "#meditative.b"
    assert state_after_second_transition === "#meditative.b" # NOTE: it didn't transition.. which is the desired behavior.
  end

  test "Meditative statecharts support the invoke feature" do
    invoke_sources = %{
      "c_invoke_src_func" => fn context ->
        {:ok, %{"data" => "Http response"}}
      end
    }

    statechart = %{
      "id" => "meditative",
      "initial_state" => "a",
      "context" => %{
        "count" => 0
      },
      "states" => %{
        "a" => %{
          "on" => %{ "DO_IT" => "d" }
        },
        "b" => %{
          "on" => %{ "DO_IT" => "c" }
        },
        "c" => %{
          "on" => %{ "DO_IT" => "c" }
        },
        "d" => %{
          "invoke" => %{
            "id" => "c_invoke_src",
            "src" => "c_invoke_src_func",
            "on_done" => "b",
            "on_error" => "c",
          }
        }
      }
    }

    machine = Meditative.interpret(statechart, %{"actions" => nil, "guards" => nil, "invoke_sources" => invoke_sources})
    state_before_transition = machine |> Map.get(:current_state)
    updated_machine = Meditative.transition(machine, "DO_IT")
    state_after_transition = updated_machine |> Map.get(:current_state)

    assert state_before_transition === "#meditative.a"
    assert state_after_transition === "#meditative.b"
  end
end
