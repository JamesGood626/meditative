defmodule Machine do

  import Cat
  alias State
  alias Transition

  defstruct [:id, :current_state, :parallel_state_key, :context, :on, :states, :actions, :guards, :invoke_sources]

  # IMMEDIATE TODO STEPS FOR COMPLETING THE THIRD REFACTOR OF THE TRANSITION SEQUENCING IMPLEMENTATION:
  # 1. Refactor def transition (w/ the changes that require implementing a list of functions to be executed in a reduce)
  # 2. Refactor def handle_transition (and a lot of the functions used inside of it (which should instead return a
  #    updated_machine... apply_actions and apply_transient_transition for example))

  # THis comment (in the nature of Software Architecture)...
  # https://www.reddit.com/r/elixir/comments/np688d/why_is_there_no_need_for_asyncawait_in_elixir/h03pttm?utm_source=share&utm_medium=web2x&context=3

  # Comment regarding BEAM VM Concurrency:
  # https://www.reddit.com/r/elixir/comments/np688d/why_is_there_no_need_for_asyncawait_in_elixir/h065lif?utm_source=share&utm_medium=web2x&context=3

  # TODO:
  # The invoke key under a state:
  # But... instead of having src capable of being defined inline, would prefer to
  # have an :invoke_sources key on the Machine, and the actual functions to be invoked must be passed in to Machine.interpret/2
  # in a similar fashion as actions and guards.
  # invoke: {
  #   id: 'getUser',
  #   src: (context, event) => fetchUser(context.userId),
  #   onDone: {
  #     target: 'success',
  #     actions: assign({ user: (context, event) => event.data })
  #   },
  #   onError: {
  #     target: 'failure',
  #     actions: assign({ error: (context, event) => event.data })
  #   }
  # }


  # IMMEDIATE TODO:
  # This design needs to be simplified...
  # transition -> (handle_transition, parallel_state_transition, determine_next_transition_step, get_transition_associated_with_event, get_target_state, get_state, get_guard, run_cond) -> apply_transient_transition -> ((apply_actions -> invoke_action -> get_action_function), run_cond, get_guard, get_target_state, get_state run_on_entry, run_on_exit)

  def get_id(statechart) do
    statechart
    |> Map.get("id")
    # TODO: Necessary to perform some kind of validation on the id?
    |> Cat.to_either("You must provide an id to the statechart")
    |> Cat.either(fn msg -> raise msg end, fn val -> val end)
    |> Cat.unwrap
  end

  @doc """
  iex> statechart = %{
  iex>    "id" => "meditative",
  iex>    "initial_state" => "p",
  iex>    "context" => %{
  iex>      "count" => 0,
  iex>      "name" => nil
  iex>    },
  iex>    "states" => %{
  iex>      "green" => %{
  iex>        "on" => %{
  iex>          "YELLOW" => "yellow"
  iex>        }
  iex>      },
  iex>      "yellow" => %{
  iex>        "type" => "final"
  iex>      }
  iex>    }
  iex>  }
  iex> Machine.get_constructed_states(statechart, "#meditative")
  %{
    "#meditative.green" => %State{
      initial_state: nil,
      name: "#meditative.green",
      on: %{
        "YELLOW" => %Transition{actions: nil, event: "YELLOW", from: "#meditative.green", guard: nil, to: "#meditative.yellow"}
      },
      on_entry: nil,
      on_exit: nil,
      parallel_states: nil,
      type: nil
    },
    "#meditative.yellow" => %State{
      initial_state: nil,
      name: "#meditative.yellow",
      on: %{},
      on_entry: nil,
      on_exit: nil,
      parallel_states: nil,
      type: "final"
    }
  }

  Stratified Design:

  Highest Level          -> Medium Level     -> Lowest Level
  get_constructed_states/2 -> construct_states/2 -> (get_state_without_sub_states/2, get_states_sub_states/2)
  """
  def get_constructed_states(statechart, id) do
    statechart
    |> Cat.maybe
    ~>> fn x -> Map.get(x, "states") end
    ~>> fn x -> construct_states(x, id) end
    ~>> fn x ->
          Enum.reduce(x, %{}, fn ({state_name, %State{} = s}, acc) ->
          Map.put(acc, state_name, s)
        end)
      end
    |> Cat.unwrap
  end

  @doc """
  iex> states = %{
  iex>    "finite_state_one" => %{
  iex>      "on" => %{ "EVENT" => "finite_state_two" }
  iex>    },
  iex>    "finite_state_two" => %{
  iex>      "on" => %{ "EVENT" => "finite_state_one" }
  iex>    }
  iex> }
  iex> Machine.get_state_without_sub_states(states, "finite_state_two")
  %{"on" => %{"EVENT" => "finite_state_one"}}
  """
  def get_state_without_sub_states(states, state_name) do
    states
    |> Cat.maybe
    ~>> fn x -> Map.get(x, state_name) end
    ~>> fn x -> Map.delete(x, "states") end
    |> Cat.unwrap
  end


  @doc """
  iex> states = %{
  iex>    "finite_state_one" => %{
  iex>      "states" => %{
  iex>         "nested_finite_state" => %{
  iex>             "on" => %{ "EVENT" => "finite_state_one" }
  iex>         }
  iex>       }
  iex>    }
  iex> }
  iex> Machine.get_states_sub_states(states, "finite_state_one")
  %{"nested_finite_state" => %{"on" => %{"EVENT" => "finite_state_one"}}}
  """
  def get_states_sub_states(states, state_name) do
    states
    |> Cat.maybe
    ~>> fn x -> x |> Map.get(state_name) end
    ~>> fn x -> x |> Map.get("states") end
    |> Cat.unwrap
  end

  def get_target_state(nil), do: nil
  def get_target_state(%Transition{} = transition) do
    transition
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :to) end # NOTE/TODO: If Exotic had flip and curry functions... could be used here.
    |> Cat.unwrap
  end

  def get_state(state, states) do
    state
    |> Cat.maybe
    ~>> fn to -> Map.get(states, to) end
    |> Cat.unwrap
  end

  def get_event(event) when is_binary(event), do: event
  def get_event(%{"type" => event}), do: event

  @doc """
  NOTE: Could test this... it is one of the lowest level functions, but just as some of the other functions
  above, it almost seems too simple to even bother testing it.
  """
  def get_action_function(machine, action) do
    machine
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :actions) end
    ~>> fn x -> Map.get(x, action) end
    |> Cat.unwrap
  end

  # This does largely the same thing as get_action_function, but with guard functions.
  def get_guard(nil), do: nil
  def get_guard(%Transition{} = transition) do
    transition
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :guard) end
    |> Cat.unwrap
  end

  @doc """
  NOTE: to support conditional transitions... transition may be an list (in addition to possibly being a map)
  This function handles that concern.. and just returns the transition to be run.
  """
  def get_transition_associated_with_event(state, %{
    "event" => event,
    # "machine" => machine,
    # "context" => context
  }) do
    state
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :on) end
    ~>> fn x -> Map.get(x, get_event(event)) end
    ~>> fn x -> x end # NOTE: x may potentially be a list
    # ~>> fn xs when is_list(xs) ->
    #         xs
    #         |> Enum.find(fn (%Transition{guard: guard}) -> run_cond(%{"machine" => machine, "guard" => guard, "context" => context})
    #                           x -> x
    #                       end)
    #        x -> x
    #     end
    |> Cat.unwrap
  end

  def get_guard_function(machine, guard) do
    machine
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :guards) end
    ~>> fn x -> Map.get(x, guard) end
    |> Cat.unwrap
  end

  def get_on_entry(state), do: Map.get(state, :on_entry)
  def get_on_exit(state), do: Map.get(state, :on_exit)

  def invoke_guard(%{"machine" => machine, "guard" => guard, "context" => context}) do
    guard_func = get_guard_function(machine, guard)

    case guard_func do
      nil -> raise "ERROR: No guard function present for #{guard} in the second argument to Machine.interpret/2"
      _ -> guard_func.(context)
    end
  end

  def invoke_action(%{"machine" => machine, "action" => action, "context" => context, "event" => event}) do
    action_func = get_action_function(machine, action)

    case action_func do
      nil -> raise "ERROR: No action function present for #{action} in the second argument to Machine.interpret/2"
      _ ->
        case action_func.(context, event) do
          {do_transition_event, context_updates} ->
            {do_transition_event, Map.merge(context, context_updates, fn _k, _v1, v2 -> v2 end)}
          context_updates ->
            Map.merge(context, context_updates, fn _k, _v1, v2 -> v2 end)
        end
    end
  end

  def apply_actions(%{
    "actions" => nil,
    "context" => context
  }) do
    {nil, context}
  end

  def apply_actions(%{
    "machine" => machine,
    "actions" => action,
    "context" => context,
    "event" => event
  }) when is_binary(action) do
    invoke_action(%{"machine" => machine, "action" => action, "context" => context, "event" => event})
  end


  def apply_actions(%{
    "machine" => machine,
    "actions" => actions,
    "context" => context,
    "event" => event
  }) when is_list(actions) do
    actions
    |> Enum.reduce({nil, context}, fn (action, {transition_event, context_acc}) ->
      # NOTE: Also had to add this case, and change the acc value from context to {transition_event, context} to support triggering transitions within actions.
      case invoke_action(%{"machine" => machine, "action" => action, "context" => context_acc, "event" => event}) do
        {do_transition_event, updated_context} -> {do_transition_event, updated_context}
        updated_context -> {transition_event, updated_context}
      end
    end)
  end

  def apply_actions(_), do: raise "ERROR: Machine.apply_actions/1 an argument that is a String or a List of Strings!"

  def run_cond(%{"guard" => nil}), do: true
  def run_cond(%{"machine" => machine, "guard" => guard, "context" => context}) do
    invoke_guard(%{"machine" => machine, "guard" => guard, "context" => context})
  end

  def run_on_exit(%{"state" => state, "machine" => machine, "context" => context, "event" => event}) do
    state
    |> get_on_exit
    |> Utils.to_list
    |> Enum.reduce(context, fn (action, updated_context) ->
      invoke_action(%{"machine" => machine, "action" => action, "context" => updated_context, "event" => event})
    end)
  end

  def run_on_entry(%{"state" => state, "machine" => machine, "context" => context, "event" => event}) do
    state
    |> get_on_entry
    |> Utils.to_list
    |> Enum.reduce(context, fn (action, updated_context) ->
      invoke_action(%{"machine" => machine, "action" => action, "context" => updated_context, "event" => event})
    end)
  end

  def apply_transient_transition(%{"transition" => nil, "context" => context, "fallback_to" => fallback_to}) do
    %{"new_context" => context, "to" => fallback_to}
  end

  def apply_transient_transition(%{
    "machine" => machine,
    "transition" => transition,
    "context" => context,
    "event" => event,
    "states" => states,
    "state" => state,
    "fallback_to" => fallback_to
    }) do
      # IMMEDIATE TODO:

      # Overall state available to the pipeline (All functions receive this as input and return it as output (wrapped in a Right/Left)):
      # %{
      #   "machine" => machine,
      #   "transition" => transition
      # }

      # Actions of a Transient Transition:
      # [
      #   {"GET_TRANSIENT_TRANSITION", get_transient_transition_fn}, Needs machine <- If nil, then short circuit rest of the steps (if a Left(OverallState) is returned)
      #   {"GET_TARGET_STATE", get_target_state_fn}, Needs machine and transition
      #   {"GET_AND_RUN_GUARDS", get_and_run_guards_fn}, Needs transition to retrieve guard from,
      #   {"GET_AND_RUN_ACTIONS", get_and_run_actions_fn}, Needs transition to retrieve actions from
      #   {"RUN_ON_EXIT", run_on_exit}, Needs machine_state, machine, new_context (from running actions), and event
      #   {"RUN_ON_ENTRY", run_on_entry} Needs machine_state, machine, new_context (from running actions), and event
      # ]

      # IMPORANT NOTE:
      # After further analysing the potential structure of the necessary pipelines
      # I realize that these steps listed in def handle_transition... can really be applied to a transient transition
      # as well.
      # So Both a transient_transition and invoke_sources can trigger a transition...
      # All they need to do is call the transition function (w/ the exception that the invoke_sources will require a new
      # function head for def transition to support the particular event data structure that's returned by executing a invoke_source)
      # ThePipeline:
        # [
          #   {"GET_AND_RUN_ACTIONS", get_and_run_actions_fn} Needs machine and transition (should return Right(updated_machine)) Shouldn't ever be a failure case...
          #   {"CHECK_IF_TRANSITION_HAS_TARGET_STATE", transition_has_to?}, <- Return Left(machine) to short circuit... as there is no finite state transition to handle.
          #   {"RUN_ON_EXIT", run_on_exit}, Needs machine_state, machine, new_context (from running actions), and event
          #   {"RUN_ON_ENTRY", run_on_entry} Needs machine_state, machine, new_context (from running actions), and event
          #   {"GET_AND_RUN_TRANSIENT_TRANSITION", get_and_run_transient_transition_fn} Should return Right(updated_machine) || Right(unmodified_machine)
          #   {"EXECUTE_INVOKE_SOURCES"} Needs machine
        # ]
        # ^^ And really checking for a transient_transition || invoke_sources should really be the last step...
        #    as only one should be present at any given time.

      # IMPORTANT_NOTE
      # Due to this pipeline being used in the handle_transition function's pipeline (that I'm sketching out currently..)
      # It's necessary to ultimately return a Right(unmodified_machine) || Right(updated_machine) as the overall return result from this function.
      # So Whether the result of the pipeline above is Right || Left (in the event that we needed to short circuit), <- that result should
      # have its machine extracted and wrapped in a Right.

      # ^^ Double check on what the output of this should be for both successful cases and failure cases in relation to the process that
      #    invokes this as some part of an action pipeline...
      # Success case return should be Right(Machine with updated current_state and context)?
      # Failure case return should be Left(Machine unmodified)?
    target_state = get_target_state_struct_via_transition(transition, states)
    case {transition, run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context})} do
      {%Transition{to: to, actions: actions}, true} ->
        {_, new_context} = apply_actions(%{
          "machine" => machine,
          "actions" => actions,
          "context" => context,
          "event" => event
        })
        # Return an updated Machine Struct with updated finite and context state.
        new_context = run_on_exit(%{"state" => state, "machine" => machine, "context" => new_context, "event" => event})
        new_context = run_on_entry(%{"state" => target_state, "machine" => machine, "context" => new_context, "event" => event})
        %{"new_context" => new_context, "to" => to}
      # vv Is this below case ever actually possible? This function shouldn't even be executing if a transition struct wasn't retrieved while looking
      # up an event = "" under a machine's transitions map.
      {_, false} ->
        %{"new_context" => context, "to" => fallback_to}
    end
  end


  @doc """
    Based on the results of:
    - transition
    - target_state
    - boolean result of run_cond

    The next course of action may either be:
    "NO_TRANSITION" -> in which case we just return the machine
    "TRANSITION" -> Where all actions (and any possible transient transitions) are applied
                    and finite and context states are updated and the new machine is returned with those updates
    "RUN_ACTIONS" -> Where the transition provided has no target attribute, in which case we just run actions and update context.
    "UNEXPECTED_ERROR"
  """
  def determine_next_transition_step(%{ "transition" => nil }), do: "NO_TRANSITION"
  # NOTE/TODO: This clause (originally %{ "target_state" => nil}) was being caught in the case where I want "RUN_ACTIONS" to be returned...
  #            make sure this doesn't error in the cases where I want it to actually return "NO_TRANSITION"
  def determine_next_transition_step(%{ "target_state" => nil, "transition" => %Transition{to: nil, actions: nil}}), do: "NO_TRANSITION"
  def determine_next_transition_step(%{ "cond_result" => false }), do: "NO_TRANSITION"

  def determine_next_transition_step(%{
    "transition" => conditional_transitions,
    "target_state" => _target_state,
    "cond_result" => _cond_result,
    "machine" => machine,
    "context" => context
  }) when is_list(conditional_transitions) do
    conditional_transitions
    |> Enum.filter(fn %Transition{guard: guard} -> run_cond(%{"machine" => machine, "guard" => guard, "context" => context})
                      x -> x
                  end)
    |> (fn [x | []] -> {"TRANSITION", x} end).()
  end

  def determine_next_transition_step(%{
    "transition" => %Transition{to: nil, actions: _actions} = transition,
    "cond_result" => true
  }) do
    {"RUN_ACTIONS", transition}
  end

  def determine_next_transition_step(%{
    "transition" => %Transition{to: _to, actions: _actions} = transition,
    "cond_result" => true
  }) do
    {"TRANSITION", transition}
  end

  def determine_next_transition_step(x), do: {"UNEXPECTED_ERROR", x}

  @doc """
  Whenever we are in a state where parallel states are active,
  the :current_state will be an array, for example:
  ["#meditative.p.region1.foo1", "#meditative.p.region2.bar2"]

  1. Retrieve both of the states under the two strings in the array above.
  2. Retrieve the map of transitions stored under both of their :on fields.
  3. Get the keys of both the transition maps, and determine which
     parallel state has a Transition for the received Event. (make sure to retain the index position
     for which state in the array should be updated to the Transition's :to value.)

  NOTE: :parallel_state_key on the Machine struct is necessary... otherwise it won't be possible
        to retrieve the particular parallel state that's the Machine is currently active in from the Machine's states map.

  For example, parallel_state_key will be #meditative.p
  """
  def get_parallel_state_transition(%Machine{current_state: current_state, parallel_state_key: parallel_state_key, states: states, context: _context, guards: _guards} = machine, event) do
    parallel_state = Map.get(states, parallel_state_key)
    state_to_update =
      parallel_state
      |> Cat.maybe
      ~>> (fn %State{parallel_states: parallel_states} ->
            states = parallel_states |> Map.get("states")
            current_state
            |> Enum.with_index
            |> Enum.reduce(nil, (fn ({x, idx}, acc) ->
              Map.get(states, x)
              |> Cat.maybe
              # ~>> fn x -> Map.get(x, states) end |> Cat.trace("After Map.get(x, states)")
              ~>> fn x -> Map.get(x, :on) end
              ~>> fn x -> Map.get(x, get_event(event)) end
              # NOTE: The reason why I'm getting a nil accumulator value....
              #       For the second parallel state string in the list of parallel states (representing the current finite state configuration)
              #       For the state which doesn't have an event which yields transition from the Map.get retrieval avoe, it will return nil...
              #       AND THEN, the monadic bind function below will never be executed (therefore whatever the last value of acc was is never set...
              #       hence the nil result.
              # ^^ Which is why I added the Cat.unwrap_with_default/2
              ~>> (fn %Transition{from: from} = transition ->
                    acc # |> Cat.trace("WTF is acc inside the ~>> that pattern matches on %Transition{}")
                    if (from === Enum.at(current_state, idx)) do

                      {idx, x, transition} # |> Cat.trace("setting acc in if statement reduce to...")
                    end
                  end)
              |> Cat.unwrap_with_default(acc)
            end))
            # |> Cat.trace("WTF is the result of parallel_state_transition after the entire reduce")
          end)
      # |> Cat.trace("Right before the last Cat.unwrap")
      |> Cat.unwrap
      |> (fn nil -> machine
              x -> x
          end).()
  end

  def handle_executing_invoke_sources(machine, context, state) do
    fn %{"id" => id, "src" => src, "on_done" => on_done, "on_error" => on_error} ->
      # 1. Grab the invoke function from the Machine struct under :invoke_sources via the src string
      # 2. Invoke the lambda function which was retrieved via the src string
      invoke_source_fn = machine |> Cat.maybe ~>> fn x -> Map.get(x, :invoke_sources) end ~>> fn x -> Map.get(x, src) end |> Cat.unwrap

      if invoke_source_fn === nil || !is_function(invoke_source_fn) do
        raise "DEVELOPER ERROR: the function provided for the invoke src #{src} under state #{state} is not a function."
      end

      task = Task.async(fn -> invoke_source_fn.(context) end)
      case Task.await(task) do
        # {transition_struct, event}
        {:ok, data} ->
          {on_done, %{"type" => "INVOKE_SOURCE_ON_DONE_TRANSITION", "invoke_id" => id, "payload" => data}}
        {:error, data} ->
          {on_error, %{"type" => "INVOKE_SOURCE_ON_ERROR_TRANSITION", "invoke_id" => id, "payload" => data}}
      end
    end
  end

  def execute_invoke_sources(machine, context, state) do
    # NOTE/FUTURE TODO: "#meditative.p.region1.foo2" <- The Map.get(state) below will return nil... because
    # it's a parallel state. Will need to fix this once I handle the refactor...

    result =
      machine
      |> Map.get(:states)
      |> Map.get(state)
      |> Cat.maybe
      ~>> fn x -> Map.get(x, :invoke) end
      ~>> handle_executing_invoke_sources(machine, context, state)
      |> Cat.unwrap

    case result do
      nil -> :no_invoke
      {transition_due_to_invoke, next_event} -> {:invoke, {transition_due_to_invoke, next_event}}
    end
  end

  def handle_transition(%{
    "next_step" => next_step,
    # "transition" => _transition,
    "machine" => machine,
    "context" => context,
    "event" => event,
    "states" => states,
    "from_state" => from_state,
    "target_state" => target_state, # Needs to be a State struct
  }) do
    case next_step do
      # [
      #  {"RUN_ACTIONS", {machine, actions, context, event}},
      #  {"RUN_ON_EXIT", {machine, actions, updated_context, event}},
      #  {"RUN_ON_ENTRY", {machine, actions, updated_context2, event}},
      #  {"RUN_ON_TRANSIENT_TRANSITION", {machine, updated_context, event = "", states, from_state, fallback_to_state}},
      # ^^vv NOTE: "RUN_ON_TRANSIENT_TRANSITION" and "RUN_INVOKE_SOURCES" are not permissible simultaneously.
      #  {"RUN_INVOKE_SOURCES", }
      # ]
      # ^^ IMMEDIATE TODO: The list which should be passed to this function AFTER handling the third refactor of the transition logic...
      #    Where the above list is generated by the handle_normal_transition and handle_parallel_transition functions.
      # I think the easiest way to implement this would be to have functions (standardized to handle a particular input/output)
      # which are specified in the desired order (in a list) in which they should run, and composed at runtime (kind of like the
      # SDfF book). <- Although that may just be overkill... and instead you can just opt for a regular |> pipeline.
      {"TRANSITION", %Transition{to: to, actions: actions}} ->
        # TODO: Had to pattern match on the tuple after adding the actions can return a tuple to trigger a transition feature...
        #       would be better if I create a function that only retrieves a new_context back if it's a regular transition we're executing
        #       otherwise get a tuple back if it's the actions feature.

        # IMMEDIATE TODO:
        # Another pipeline... (after having noted out the pipeline in apply_transient_transition; the two pipeline needs to be compatible)
        # OverallState = %{
        #   "machine" => machine,
        #   "event" => event,
        #   "transition" => transition,
        # }

        # ThePipeline:
        # [
          #   {"GET_AND_RUN_ACTIONS", get_and_run_actions_fn} Needs machine and transition (should return Right(updated_machine)) Shouldn't ever be a failure case...
          #   {"CHECK_IF_TRANSITION_HAS_TARGET_STATE", transition_has_to?}, <- Return Left(machine) to short circuit... as there is no finite state transition to handle.
          #   {"RUN_ON_EXIT", run_on_exit}, Needs machine_state, machine, new_context (from running actions), and event
          #   {"RUN_ON_ENTRY", run_on_entry} Needs machine_state, machine, new_context (from running actions), and event
          #   {"GET_AND_RUN_TRANSIENT_TRANSITION", get_and_run_transient_transition_fn} Should return Right(updated_machine) || Right(unmodified_machine)
          #   {"EXECUTE_INVOKE_SOURCES"} Needs machine
        # ]

        # IMMEDIATE TODO:
        # Refactor apply_actions to return the machine with the updated_context after running actions
        {_, new_context} = apply_actions(%{
          "machine" => machine,
          "actions" => actions,
          "context" => context,
          "event" => event
        })

        # IMMEDIATE TODO:
        # Refactor run_on_exit && run_on_entry to return the machine with the updated_context after running actions
        # Return an updated Machine Struct with updated finite and context state.
        new_context = run_on_exit(%{"state" => from_state, "machine" => machine, "context" => new_context, "event" => event})
        new_context = run_on_entry(%{"state" => target_state, "machine" => machine, "context" => new_context, "event" => event})

        # NOTE: target_state is set on the OverallState (within the handle_normal_transition && handle_parallel_transition functions)
        transient_transition = target_state |> get_transition_associated_with_event(%{
          "event" => "",
          "machine" => machine,
          "context" => new_context # <- Why didn't I pass in new_context here? context or new_context... either don't break tests
        })
        %{"new_context" => new_context, "to" => to} =
              apply_transient_transition(%{"machine" => machine, "transition" => transient_transition, "context" => new_context, "event" => event, "states" => states, "state" => from_state, "fallback_to" => to})
        # LLO/IMMEDIATE TODO: Without going through a major refactor... I believe this is the location
        # where handling calling the invoke_source provided by the user.
        # How does this resolve when there's both a transient transition and an invoke source?!
        # ^^ Or should this be an invariant which should never be allowed, i.e. no transient transition and invoke source
        # may be defined simultaneously for any given state.
        # Implementing the invariant is really easy... create a function which takes in the result of getting the transient transition
        # and the result of getting any potential declared invoke sources, pass both into a function
        # one or the other should be nil (pattern matched in the head of a multiclause funcion), else the third case
        # will be the error warning the user of an invalid declaration (BUT this is a rather late time to warn of this...
        # would be better to maintain this invariant during the Machine.interpret/2 phase, however this could work for temporary purposes).

        # ^^ Then the apply_transient_transition would be invoked inside of that function which maintains the invariant, or the
        # function which actually invokes the invoke_source.
        # The function which invokes the invoke source, will use
        # task = Task.async(fn -> function_user_gave_as_invoke_src end)
        # and Task.await(task)
        # The user's function provided as invoke_src MUST return either {:ok, val} || {:err, msg}
        # The return result of which will be used to determine whether to invoke onDone or onError.
        # iex(3)> task = Task.async(fn -> {:ok, "jdsajkda"} end)
        # %Task{
        #   owner: #PID<0.106.0>,
        #   pid: #PID<0.111.0>,
        #   ref: #Reference<0.1819233756.2573467651.99064>
        # }
        # iex(4)> Task.await(task)
        # {:ok, "jdsajkda"}
        # iex(5)> task = Task.async(fn -> {:error, "jdsajkda"} end)
        # %Task{
        #   owner: #PID<0.106.0>,
        #   pid: #PID<0.114.0>,
        #   ref: #Reference<0.1819233756.2573467651.99087>
        # }
        # iex(6)> Task.await(task)
        # {:error, "jdsajkda"}

        # There's one more subtle aspect to the invoke feature in relation to this transition/2 function...
        # Handling invoke will typically be done after having transitioned successfully to the target state.
        # So we need to retrieve the target_state that will be set to the current_state below, and then check if there's
        # any registered invoke source, if so then we go through the process outlined above, and potentially transitioning
        # to the states declared on the onDone/onError keys.

        # vv TODO: Make sure the reason you chose to access :initial_state within the monad context below
        # is because you want to make sure that if an initial_state is present in the state which is being transitioned to
        # that we update the machine's current_state to that value, and if not then we just set it as the state assigned under
        # the Transition struct's 'to' key. (If this is the case, then create a single function for this and doctest it)
        # .WTF is target_state before execute_invoke_sources
        # %State{
        #   initial_state: nil,
        #   invoke: nil,
        #   name: "#meditative.p.region1.foo2",
        #   on: %{
        #     "TO_FOO_1" => %Transition{
        #       actions: nil,
        #       event: "TO_FOO_1",
        #       from: "#meditative.p.region1.foo2",
        #       guard: nil,
        #       to: "#meditative.p.region1.foo1"
        #     }
        #   },
        #   on_entry: nil,
        #   on_exit: nil,
        #   parallel_states: nil,
        #   type: nil
        # }
        ending_state = target_state |> Cat.maybe ~>> fn x -> Map.get(x, :initial_state) end |> Cat.unwrap || to
        case execute_invoke_sources(machine, new_context, ending_state) do
          :no_invoke ->
            %{machine | current_state: ending_state, context: new_context}

          {:invoke, {%{"target" => to} = transition_map, next_event}} ->
            # {on_done, %{"type" => "INVOKE_SOURCE_ON_DONE_TRANSITION", "invoke_id" => id, "payload" => data}}
            # {on_error, %{"type" => "INVOKE_SOURCE_ON_ERROR_TRANSITION", "invoke_id" => id, "payload" => data}}
            handle_transition(%{
              "next_step" => {"TRANSITION", %Transition{to: transition_map |> Map.get("to"), actions: transition_map |> Map.get("actions")}},
              "machine" => machine,
              "context" => new_context,
              "event" => next_event,
              "states" => states,
              "from_state" => Map.get(machine, :states) |> Map.get(ending_state),
              "target_state" => Map.get(machine, :states) |> Map.get(to), # TODO: Would probably be a good idea to use Either here...
            })

          {:invoke, {to, next_event}} ->
            # {on_done, %{"type" => "INVOKE_SOURCE_ON_DONE_TRANSITION", "invoke_id" => id, "payload" => data}}
            # {on_error, %{"type" => "INVOKE_SOURCE_ON_ERROR_TRANSITION", "invoke_id" => id, "payload" => data}}
            handle_transition(%{
              "next_step" => {"TRANSITION", %Transition{to: to}},
              "machine" => machine,
              "context" => new_context,
              "event" => next_event,
              "states" => states,
              "from_state" => Map.get(machine, :states) |> Map.get(ending_state),
              "target_state" => Map.get(machine, :states) |> Map.get(to),
            })
        end

        # TODO: Add code to enable actions (associated with a Transition that doesn't specify a target)
        #       to trigger transitions by returning {"TRANSITION_TO_TRIGGER", payload}
        # Would just need to invoke:
        # transition(%Machine{current_state: current_state, states: states, context: context, guards: guards} = machine, event)
        # ^^ In the case that the action returns the tuple to trigger a transition. <- So yeah... this would be really easy to add.
      {"RUN_ACTIONS", %Transition{actions: actions}} ->
        # NOTE: Commented lines is what was ran for "RUN_ACTIONS" before adding the ability
        #       to trigger transitions from a event which only runs actions.
        # new_context = apply_actions(%{
        #   "machine" => machine,
        #   "actions" => actions,
        #   "context" => context,
        #   "event" => event
        # })
        # %{machine | context: new_context}

        # WARNING: This feature does come at a cost...
        #          The possibility of transitioning between two different finite states
        #          that have actions which transition to another finite state which again transitions... and
        #          could do so infinitely many times is a possibility.
        #          So this feature must be used with care.
        case apply_actions(%{
          "machine" => machine,
          "actions" => actions,
          "context" => context,
          "event" => event
        }) do
          {nil, new_context} -> %{machine | context: new_context}
          {transition_event, new_context} ->
            updated_machine = %{machine | context: new_context}
            # NOTE: Unsure if I should leave this... but I will for now.
            Machine.transition(updated_machine, transition_event)
        end
      "NO_TRANSITION" ->
        machine
      {"UNEXPECTED_ERROR", x} ->
        IO.inspect(x)
        raise "UNEXPECTED ERROR: in Machine.transition/2"
    end
  end

  def get_from_state_struct_from_parallel_state(parallel_states, from) do
    parallel_states |> Cat.maybe ~>> fn x -> Map.get(x, from) end |> Cat.unwrap
  end


  def get_from_state_struct_from_machine(%Machine{current_state: current_state}, states) do
    states |> Cat.maybe ~>> fn x -> Map.get(x, current_state) end |> Cat.unwrap
  end

  def get_target_state_struct_via_transition(transition, states) do
    transition |> get_target_state |> get_state(states)
  end

  def get_parallel_states(machine) do
    parallel_state_key = machine |> Map.get(:parallel_state_key)
    if parallel_state_key === nil do raise "OPEN SOURCE DEVELOPER ERROR: If state is in a parallel configuration, then :parallel_state_key on %Machine{} should never be nil!!!" end
    machine |> Map.get(:states) |> Map.get(parallel_state_key) |> Map.get(:parallel_states) |> Map.get("states")
  end

  def update_current_state_parallel_configuration(current_state, idx, to) do
    List.update_at(current_state, idx, fn _ -> to end)
  end

  # LLO/TODO:
  # next step would be to see if I can get a majority of the parallel_states/states/target_state/next_step
  # variable assignments in both handle_parallel_transition/1 and handle_normal_transition/1
  # to be in a single function which can be reused in both... (and create the pipeline in such a way
  # that it's extensible in the future for any additional features to be added.)

  # The GENERAL STRUCTURE of handle_parallel_transition and handle_normal_transition:
  # get states || parallel_states -> get from_state -> get transition -< get target_state -> generate next_step tuple -> handle_transition
  #      -> extra step for parallel state transition, to check if to is a possible parallel state (transitioning between another parallel state
  #                                                                                               or transitioning out of the parallel states)
  # ^^ Will work on reworking this to a better solution later...
  def handle_parallel_transition(%{
    "machine" => %Machine{current_state: current_state, states: states, context: context} = machine,
    "event" => event,
  }) do
    case get_parallel_state_transition(machine, event) do # |> Cat.trace("Result of parallel_state_transition")
        {idx, _from, %Transition{to: to, from: from} = transition} ->
          # TODO: Fix the disconnect between the sequencing of whether this transition is within a parallel
          # and the retrieval of the parallel states... (referring to the is_list check in transition, but this may
          # be smaller issue than I'm making it out to be.)
          parallel_states = get_parallel_states(machine)

          from_state = get_from_state_struct_from_parallel_state(parallel_states, from)
          # transition |> Cat.trace("transition in the pattern match on parallel_state_transition(machine, event)")

          # NOTE: Implement something better than this... the part the follows after || is meant to handle cases where we're transitioning
          #       out of the parallel state configuration.
          target_state = get_target_state_struct_via_transition(transition, parallel_states) || get_target_state_struct_via_transition(transition, states)
          next_step = determine_next_transition_step(%{
            "transition" => transition,
            "target_state" => target_state,
            "cond_result" => run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context}),
            "machine" => machine,
            "context" => context
          })
          # next_step |> Cat.trace("got next step for parallel transition")

          # Need to know if the transition is going to be:
          #   - into one of the possible parallel states... (in which case we update the current_state list at the appropriate index)
          #   - outside of the parallel state, in which case we set current_state to the transition's :to field, and set parallel_state_key on the
          #     machine to nil
          # To determine if it is a transition to another parallel state... we'll take the get keys of the parallel states into a list
          # and run a simple transition.to in list_of_parallel_state_names check.
          possible_parallel_states = parallel_states |> Map.keys # |> Cat.trace("the Map.keys of the parallel_states")
          updated_machine = handle_transition(%{
            "next_step" => next_step,
            "transition" => transition,
            "machine" => machine,
            "context" => context,
            "event" => event,
            "states" => parallel_states,
            "from_state" => from_state,
            "target_state" => target_state,
          })

          if to in possible_parallel_states do
            # A transition into a parallel state
            %{updated_machine | current_state: update_current_state_parallel_configuration(current_state, idx, to)}
          else
            # A transition out of the parallel state
            %{updated_machine | parallel_state_key: nil}
          end

        machine ->
          # Transition for the event wasn't present in any of the parallel states.
          machine
      end
  end

  def handle_normal_transition(%{
    "machine" => %Machine{states: states, context: context} = machine,
    "event" => event
  }) do
    # IMMEDIATE TODO
    # PipelineOverallState = %{
    #   "machine" => machine,
    #   "event" => event,
    #   "from_state" => from_state, # :: %State{} Placed on state via the get_from_state_struct_from_machine function
    #   "target_state" => target_state, # :: %State{} Placed on state via the get_target_state_struct_via_transition function
    #   "transition" => transition, # %Transition{} Placed on state via the get_transition_associated_with_event function
    # }

    # ^^ Doing this... Along with the other Pipeline functions in the lower levels, should make the determine_next_transition_step/1 function redundant.
    # This is less similar to the other pipelines I've sketched out..
    # The structure of what needs to occur is more along the lines of reducing over a list of functions
    # (which each use the acc value to fetch the value needed and return the acc value updated with whatever they retrieved;
    # AND ultimately... the last function in the pipeline will return the machine updated after the transition steps have occured)


      # NOTE: Doing a normal state transition
      # do_normal_state_transition(%{
      #   "machine" => machine,
      #   "context" => context,
      #   "states" => states,
      # })

      # 1. get the from_state from the state map
      # 2. get the transition from the from state (alternatively, could be a global transition...).
      # 3. get the target state from the state map
      # 4. Get the next_step action (uses the target_state and transition results from steps 2 and 3 above)
      # 5. next_step is passed to handle_transition... which actually does a lot of the sequencing of
      #    invoking actions, guards, and possible declared invoke sources

      # from_state = states |> Cat.maybe ~>> fn x -> Map.get(x, current_state) end |> Cat.unwrap
      from_state = get_from_state_struct_from_machine(machine, states)
      # global_transition = machine |> get_transition_associated_with_event(%{
      #   "event" => event,
      #   "machine" => machine,
      #   "context" => context
      # })

      # THE OLD WAY I CALLED THIS...
      # transition = from_state |> get_transition_associated_with_event(%{
      #   "event" => event,
      #   "machine" => machine,
      #   "context" => context
      # })

      # TESTING/TODO
      # if global_transition !== nil && transition !== nil do
      #   raise "DEVELOPER ERROR: You may not have transitions with the same name on the global 'on' transitions map and in \
      #          a specific finite state's 'on' transition map. event: #{event} current_state: #{current_state}"
      # end

      # blah
      # IMPORTANT NOTE/TODO:
      # Going to need to write more tests for this to make sure it works in more scenarios... but for now this is the desired behavior... despite how terrible this code looks.
      case get_transition_associated_with_event(from_state, %{ "event" => event }) do
        transitions when is_list(transitions) ->
          {_, updated_machine} = transitions
          |> Enum.reduce({:continue, machine}, fn (%Transition{guard: nil, to: nil} = transition, {:continue, %Machine{context: context} = machine}) ->
                                                    target_state = get_target_state_struct_via_transition(transition, states)

                                                    next_step = determine_next_transition_step(%{
                                                      "transition" => transition,
                                                      "target_state" => target_state,
                                                      "cond_result" => run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context}),
                                                      "machine" => machine,
                                                      "context" => context
                                                    })

                                                    updated_machine = handle_transition(%{
                                                      "next_step" => next_step,
                                                      "transition" => transition,
                                                      "machine" => machine,
                                                      "context" => context,
                                                      "event" => event,
                                                      "states" => states,
                                                      "from_state" => from_state,
                                                      "target_state" => target_state,
                                                    })
                                                    {:continue, updated_machine}
                                                  (%Transition{guard: guard} = transition, {:continue, %Machine{context: context} = machine}) ->
                                                    handle_transition_with_guard(%{
                                                      "machine" => machine,
                                                      "guard" => guard,
                                                      "context" => context,
                                                      "event" => event,
                                                      "transition" => transition,
                                                      "states" => states,
                                                      "from_state" => from_state
                                                    })
                                                  (_, {:ignore_rest, machine}) -> machine

          end)

          updated_machine

        transition ->
          target_state = get_target_state_struct_via_transition(transition, states)

          next_step = determine_next_transition_step(%{
            "transition" => transition,
            "target_state" => target_state,
            "cond_result" => run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context}),
            "machine" => machine,
            "context" => context
          })

          handle_transition(%{
            "next_step" => next_step,
            "transition" => transition,
            "machine" => machine,
            "context" => context,
            "event" => event,
            "states" => states,
            "from_state" => from_state,
            "target_state" => target_state,
          })
      end

      # |> Cat.to_either("ERROR: Attempted to transition to the state: #{get_target_state(transition)}, that is not declared on the statechart!")
      # |> Cat.either(fn msg -> raise msg end, &Cat.id/1)
      # |> Cat.unwrap
  end

  def handle_transition_with_guard(%{
    "machine" => machine,
    "guard" => guard,
    "context" => context,
    "event" => event,
    "transition" => transition,
    "states" => states,
    "from_state" => from_state
  }) do
    if run_cond(%{"machine" => machine, "guard" => guard, "context" => context}) do
      target_state = get_target_state_struct_via_transition(transition, states)

      next_step = determine_next_transition_step(%{
        "transition" => transition,
        "target_state" => target_state,
        "cond_result" => run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context}),
        "machine" => machine,
        "context" => context
      })

      updated_machine = handle_transition(%{
        "next_step" => next_step,
        "transition" => transition,
        "machine" => machine,
        "context" => context,
        "event" => event,
        "states" => states,
        "from_state" => from_state,
        "target_state" => target_state,
      })

      {:ignore_rest, updated_machine}
    else
      {:continue, machine}
    end
  end

  # TODO:
  # event can be either a string or a map which stores the string under the key :type + any arbitrary key the user wants to use
  # to establish some kind of additional metadata for the transition.
  def transition(%Machine{current_state: current_state} = machine, event) when is_list(current_state), do: handle_parallel_transition(%{"machine" => machine, "event" => event})
    # 1. Retrieve current_state from machine
    # current_state = machine |> Map.get("current_state") |> IO.inspect
    #   1a.
    #      2a. Check if the current_state is a parallel state... (if it's a list)
    #          If so, then run the steps in the moduledoc of the Machine module.
    #   1b.
    #       2b. retrieve the corresponding current_state Struct from the states list
    #       IO.puts("THE MACHINE IN TRANSITION/2")
    #       IO.inspect(machine)

    # transition -> (handle_transition, parallel_state_transition, determine_next_transition_step, get_transition_associated_with_event, get_target_state, get_state, get_guard, run_cond)
    #            -> is_parallel_state? (true)  -> parallel_state_transition -> (get_state, get_guard, determine_next_transition_step) -> transitioning_to_another_parallel_state
    #                                  (false) -> normal_state_transition ->                                                                                                                          -> transitioning_out_of_the_parallel_state
  #   if is_list(current_state) do
  #     handle_parallel_transition(%{"machine" => machine, "event" => event})
  #   else
  #     handle_normal_transition(%{"machine" => machine, "event" => event})
  #   end
  # end
  def transition(%Machine{} = machine, event), do: handle_normal_transition(%{"machine" => machine, "event" => event})
  # IMMEDIATE TODO:
  # If I go through with the third refactor of the transition logic... then you'll need to have another transition function head
  # to support handling a transition when provided with the output of the handle_execute_invoke_sources function:
  # {%{"target" => to} = transition_map, next_event}} || {to :: String, next_event}

  def new(%{
    # "initial_state" => initial_state,
    "id" => id,
    "current_state" => current_state,
    "context" => context,
    # "on" => on,
    "states" => states,
    "actions" => actions,
    "guards" => guards,
    "invoke_sources" => invoke_sources
  } = rest) do
    %__MODULE__{
      id: id,
      current_state: current_state,
      parallel_state_key: rest |> Map.get("parallel_state_key"),
      context: context,
      # on: on,
      states: states,
      actions: actions,
      guards: guards,
      invoke_sources: invoke_sources,
      # send: &transition/2 # fn (machine, event) -> transition(machine, event) end
    }
  end

  def get_target_and_actions(%{"target" => target} = rest), do: {target, rest}
  def get_target_and_actions(%{"actions" => actions}), do: {nil, %{"actions" => actions}}
  def get_target_and_actions(target), do: {target, nil}
  def extract_transition(x) do
    x
    |> Cat.maybe
    ~>> fn xs when is_list(xs) -> xs |> Enum.map(&get_target_and_actions/1)
                   x -> get_target_and_actions(x)
        end
    |> Cat.unwrap
  end

  def make_relative_transition_string_path(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}) do
    # OLD NOTES:
    # And allows the user of the API to specify a transition from a child state into a different parent state.
    # If the state being transitioned to is a child state... we need to include state_name as is,
    # OTHERWISE if it's a state at the same level as the from state, we need to use current_level_state_name
    cond do
      to in Utils.safe_list(sibling_states) ->
        current_level_state_name = state_name |> String.split(".") |> Utils.remove_last |> Enum.join(".")
        "#{current_level_state_name}.#{to}"
      to in Utils.safe_list(child_states) ->
        "#{state_name}.#{to}"
      to === nil ->
        # NOTE/TODO: Make sure this change isn't breaking anything
        #            But this change is necessary, otherwise the "RUN_ACTIONS" case clause in handle_transitions
        #            never executes.
        # state_name
        nil
      true -> raise "ERROR: You specified a target state of '#{to}', but it isn't a sibling or child of the state that you're attempting to transition out of. Include an absolute path to target a higher level state or include the necessary sibling or child state in the statechart."
    end
  end

  # def make_target_state_name(%{"to" => xs, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}) when is_list(xs) do
  #   xs
  #   |> Enum.map(fn to ->
  #     make_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states})
  #   end)
  # end
  @doc """
  Strive to have unique names for top level states and child states in the statechart... otherwise I'll need to rewrite this code.

  EXAMPLE USAGE (This function is used when constructing transitions, and it's done recursively... so state_name will be built up during that
  #              recursion...)

  # This is the case of creating the transition string for a nested_state
  iex> Machine.make_target_state_name(%{"to" => "nested_first_step", "state_name" => "#meditative.first_step", "sibling_states" => ["first_step", "second_step"], "child_states" => ["nested_first_step", "to_the_right"]})
  "#meditative.first_step.nested_first_step"
  # %{
  #   "RUN" => %Transition{
  #     actions: "increment",
  #     event: "RUN",
  #     from: "#meditative.first_step",
  #     to: "#meditative.first_step.nested_first_step"
  #   }
  # }

  # This is the case of creating the transition string for a sibling_state
  iex> Machine.make_target_state_name(%{"to" => "second_step", "state_name" => "#meditative.first_step", "sibling_states" => ["first_step", "second_step"], "child_states" => ["nested_first_step", "to_the_right"]})
  "#meditative.second_step"

  ^^ the results above are due to the functionality provided via make_relative_transition_string_path/1

  # THIS was the state transition that I noticed was a problem, because I was outputting "#meditative.first_step.nested_first_step.to_the_right" instead (TODO: update older docs that showed a transition to of the string to the left)
  make_target_state_name(%{"to" => "to_the_right", "state_name" => state_name, "sibling_states" => ["nested_first_step", "to_the_right"], "child_states" => ["to_the_left", "two_levels_deep_nested_step"]})
  %{
    "SLIDE" => %Transition{
      actions: nil,
      event: "SLIDE",
      from: "#meditative.first_step.nested_first_step",
      to: "#meditative.first_step.to_the_right"
    }
  }
  """
  def make_target_state_name(%{"to" => to} = x) do
    # IMMEDIATE TODO: Zenith was failing to start due to "to" being nil when String.at was called...
    # Need to refine this so that whatever the statechart interprets doesn't crash...
    # If to is nil, nothing should be done...

    # NOTE: This is why to can potentially be nil...
    # the DSL
    # {nil, %{"actions" => "increment_and_transition_finite_state"}}
    # wtf is does a proper constructed transition look like
    # %Transition{
    #   actions: "increment_and_transition_finite_state",
    #   event: "DO_IT",
    #   from: "#meditative.a",
    #   guard: nil,
    #   to: nil
    # }
    # ^^ For Cases where we don't have a target state, but only run actions upon retrieval of the EVENT.
    to
    |> Cat.maybe
    ~>> fn to ->
      # NOTE: This is to ensure that we have a path from #statechart_id.nested_state
      if String.at(to, 0) === "#" do to else make_relative_transition_string_path(x) end
    end
    |> Cat.unwrap
  end

  # LLO/TODO:
  # Just trying to work out a good doctest for this...
  # Keep getting state's for to and from which don't have the state_name prepended
  @doc """
  dsl = domain service language? Think that's the acronym.
  # dsl_transitions = [{"to_the_left", %{"actions" => "increment", "target" => "to_the_left"}}, {"to_the_right", nil}]

  Example DSL = {"to_the_left", %{"actions" => "increment", "target" => "to_the_left"}}

  iex> dsl_transitions = [{"turn", nil}]
  iex> x = %{"event" => "TO_BAR1", "child_states" => nil, "sibling_states" => ["flop", "river", "turn"]}
  iex> Machine.construct_list_of_transitions(dsl_transitions, x, "#meditative.p.region1.foo1.flop")
  [%Transition{actions: nil, event: "TO_BAR1", from: "#meditative.p.region1.foo1.flop", guard: nil, to: "#meditative.p.region1.foo1.turn"}]

  # [%Transition{actions: "increment", event: "END_BETTING", from: "#meditative", guard: nil, to: ".to_the_left"}, %Transition{actions: nil, event: "END_BETTING", from: "#meditative", guard: nil, to: ".to_the_right"}]

  """
  def construct_list_of_transitions(dsl_transitions, %{"event" => event, "sibling_states" => sibling_states, "child_states" => child_states}, state_name) do
    dsl_transitions
    |> Enum.map(fn {to, rest} ->
      Transition.new(%{
        "event" => event,
        "from" => state_name, # NOTE: <- I was confused as to why the result of this function was outputting strigns such as ".flop", it was because
                              # the function inside of transition that's responsible for constructing the state names splices the string, and omits
                              # the last string at the end of the list (i.e. attempting to get rid of the .flop from the from_state in order to
                              # append .turn to create the to_state.)
        "to" => make_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}),
        "actions" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "actions") end |> Cat.unwrap,
        "guard" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "guard") end |> Cat.unwrap
      })
    end)
  end

  def get_events_from_transitions(transitions), do: transitions |> Cat.maybe ~>> fn x -> Map.keys(x) end |> Cat.unwrap |> Utils.safe_list

  @doc """
  > s |> String.split(".") |> Enum.slice(0, 2)
  ["#meditative", "first_step"]
  > s |> String.split(".") |> Enum.slice(0, 1)
  ["#meditative"]
  """
  def construct_transitions(nil, _), do: nil
  def construct_transitions(%{"transitions" => transitions, "sibling_states" => sibling_states, "child_states" => child_states} = x, state_name) do
    get_events_from_transitions(transitions)
    |> Enum.reduce(%{}, fn (event, acc) ->
      dsl_transitions = transitions |> Map.get(event) |> extract_transition
      # NOTE: cases required to support an event having an array of transitions...
      case dsl_transitions do
        {to, rest} ->
          transition = Transition.new(%{
            "event" => event,
            "from" => state_name,
            "to" => make_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}),
            "actions" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "actions") end |> Cat.unwrap,
            "guard" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "guard") end |> Cat.unwrap
          })
          # TODO: would be nice if I could curry the Map.put with event...
          acc |> Map.put(event, transition)
        xs ->
          transitions = construct_list_of_transitions(xs, Map.put(x, "event", event), state_name)
          acc |> Map.put(event, transitions)
      end
    end)
  end

  # TODO: Would really want this to raise an error if false is retrieved...
  # but the conditionals are something else right now...
  def confirm(true, error_lambda), do: error_lambda.()
  def confirm(false, _), do: nil

  def is_invalid_parallel_state?(keys, further_nested), do: length(keys) < 2 && (not further_nested) # length(keys) >= 2 && further_nested
  # length(keys) < 2 && (not further_nested)
  # true && not false <- the failure case

  # true && true

  # NOTE: Because map can potentially be nil... causing a runtime error.
  def safe_get_keys_of_map(the_map), do: the_map |> Cat.maybe ~>> fn x -> Map.keys(x) end |> Cat.unwrap || []

  def get_grand_child_states(parent_keys, parent_states) do
    parent_keys
    |> Enum.map(fn parent_key ->
      parent_states
      |> Cat.maybe
      ~>> fn x -> Map.get(x, parent_key) end
      ~>> fn x -> Map.get(x, "states") end
      |> Cat.unwrap
    end)
  end

  # TODO: doctest
  def make_parallel_state_name_string_path(grand_child_states, child_state_names) do
    # OLD NOTE:
    # [
    #   %{
    #     "foo1" => %{"on" => %{"TO_FOO_2" => "foo2"}},
    #     "foo2" => %{"on" => %{"TO_FOO_1" => "foo1"}}
    #   },
    #   %{"bar1" => %{"type" => "final"}, "bar2" => %{"type" => "final"}}
    # ]
    # 1. For each map in the grand_child_states list, need to get a list of the
    #    state names that are keys on the map and be returned in the form of a list of lists of strings.
    #    The result of the list below of "#{state_name}.#{x}" will need to have each of the state
    #    names in each of the sub lists of the grand_child_states appended to each of the strings in the child names list (with
    #    the string at index 0 having all of the strings in the sub list at index 0 appended)
    # For example:
    # child_states = ["#meditative.p.region1", "#meditative.p.region2"]
    # grand_child_states = [ ["foo1", "foo2"], ["bar1"] ]
    # result = [ ["#meditative.p.region1.foo1", "#meditative.p.region1.foo2"], ["#meditative.p.region2.bar1"] ]
    # The result and the respective grand_child_states map at the corresponding index, will then need to be recursively
    # passed down to create_parallel_state_names once more.
    grand_child_states
    |> Enum.with_index
    |> Enum.map(fn ({m, idx}) ->
          # Cat.trace(m, "WTF is m")
          # WTF is m
          # %{"bar1" => %{"type" => "final"}, "bar2" => %{"type" => "final"}}
          # "#meditative.p.region2"
          # WTF is child_state_names
          # ["#meditative.p.region1", "#meditative.p.region2"]
          # WTF is combined_state_names
          # ["#meditative.p.region1.foo1", "#meditative.p.region1.foo2",
          # "#meditative.p.region2.bar1", "#meditative.p.region2.bar2"]
          # Cat.trace(child_state_names, "WTF is child_state_names")
          child_state_name = child_state_names |> Enum.at(idx)
          m |> Map.keys |> Enum.map(fn x -> "#{child_state_name}.#{x}" end)
        end)
    |> Enum.flat_map(fn x -> x end)
  end

  # TODO: Doctest.... inrelation to the context it's used in
  def are_children_states_not_present?(child_states), do: child_states |> Enum.all?(fn x -> x === nil end)


  @doc """
  > s = "#meditative.p.region1.foo1"
  "#meditative.p.region1.foo1"
  > key = "foo1"
  "foo1"
  > s |> String.split(".")
  ["#meditative", "p", "region1", "foo1"]
  > s |> String.split(".") |> Enum.at(-1) === key
  true

  iex> xs = ["#meditative.p.region1.foo1", "#meditative.p.region1.foo2", "#meditative.p.region2.bar1", "#meditative.p.region2.bar2"]
  iex> Machine.get_full_state_string_path_with_child_finite_state_string(xs, "foo1")
  "#meditative.p.region1.foo1"
  """
  def get_full_state_string_path_with_child_finite_state_string(xs, key) do
    xs |> Enum.filter(fn x -> x |> String.split(".") |> Enum.at(-1) === key end) |> Enum.at(0)
  end

  def make_intermediate_state_representation_from_dsl_with_possible_child_states(grand_child_states, combined_state_names) do
    # The grand_child_states the first arg of make_intermediate_state_representation_from_dsl_with_possible_child_states
    # [
    #   %{
    #     "foo1" => %{
    #       "on" => %{"GTFO" => "#meditative.first_step", "TO_FOO_2" => "foo2"},
    #       "states" => %{
    #         "flop" => %{"on" => %{"END_BETTING" => "turn"}},
    #         "river" => %{"type" => "final"},
    #         "turn" => %{"on" => %{"END_BETTING" => "river"}}
    #       }
    #     },
    #     "foo2" => %{"on" => %{"TO_FOO_1" => "foo1"}}
    #   },
    #   %{"bar1" => %{"type" => "final"}, "bar2" => %{"type" => "final"}}
    # ]
    # The combined_state_names the second arg of make_intermediate_state_representation_from_dsl_with_possible_child_states
    # ["#meditative.p.region1.foo1", "#meditative.p.region1.foo2",
    #  "#meditative.p.region2.bar1", "#meditative.p.region2.bar2"]

    grand_child_states
    |> Enum.map(fn m ->
        m
        |> Cat.maybe
        ~>> fn x -> Map.keys(x) end
        # keys = ["foo1", "foo2"]
        ~>> (fn keys -> keys |> Enum.map(fn key ->  {key, Map.get(m, key)} end) end)
        # ~>> fn x -> Cat.trace(x, "{key, map.get(m, key)") end
        # ~>> fn xs -> Cat.trace(xs, "WTF is going into the line that I'm attempting to interpret...") end
        # [
        #   %{
        #       "on" => %{"GTFO" => "#meditative.first_step", "TO_FOO_2" => "foo2"},
        #       "states" => %{
        #         "flop" => %{"on" => %{"END_BETTING" => "turn"}},
        #         "river" => %{"type" => "final"},
        #         "turn" => %{"on" => %{"END_BETTING" => "river"}}
        #       }
        #    },
        #    %{"on" => %{"TO_FOO_1" => "foo1"}}
        # ]
        ~>> (fn xs ->
            # WTF is combined_state_names result
            # ["#meditative.p.region1.foo1", "#meditative.p.region1.foo2",
            #   "#meditative.p.region2.bar1", "#meditative.p.region2.bar2"]
            # combined_state_names |> Enum.at(idx) <- introduces yet another disconnect...
            # IMPORTANT NOTE: As there's some amount of coordination which should take place between make_parallel_state_name_string_path/2 and the line below
            # "states" => %{
            #   "flop" => %{"on" => %{"END_BETTING" => "turn"}},
            #   "river" => %{"type" => "final"},
            #   "turn" => %{"on" => %{"END_BETTING" => "river"}}
            # }
            xs
            |> Enum.map(fn {key, %{"states" => states}} -> {get_full_state_string_path_with_child_finite_state_string(combined_state_names, key), states}
                          {key, _} -> {get_full_state_string_path_with_child_finite_state_string(combined_state_names, key), nil}
            end)
          end)
        |> Cat.unwrap
      end)

      # [
      #   [
      #     {"#meditative.p.region1.foo1",
      #      %{
      #        "flop" => %{"on" => %{"END_BETTING" => "turn"}},
      #        "river" => %{"type" => "final"},
      #        "turn" => %{"on" => %{"END_BETTING" => "river"}}
      #      }},
      #     {"#meditative.p.region1.foo1", nil}
      #   ],
      #   [{"#meditative.p.region1.foo2", nil}, {"#meditative.p.region1.foo2", nil}]
      # ]
      # ^^ This is an erroneous result... The states for bar1 and bar2 aren't being represented.

      # The actual correct result... (surprisingly all tests still pass with that change)
      # [
      #   [
      #     {"#meditative.p.region1.foo1",
      #      %{
      #        "flop" => %{"on" => %{"END_BETTING" => "turn"}},
      #        "river" => %{"type" => "final"},
      #        "turn" => %{"on" => %{"END_BETTING" => "river"}}
      #      }},
      #     {"#meditative.p.region1.foo2", nil}
      #   ],
      #   [{"#meditative.p.region2.bar1", nil}, {"#meditative.p.region2.bar2", nil}]
      # ]
  end

  @doc """
  TODO: Make sure that the output of this function actually has an impact on the parallel state feature...
        Seems more like it's just creating state path strings for children states...

  iex> xs = [
  iex>  [
  iex>    {"#meditative.p.region1.foo1",
  iex>      %{
  iex>        "flop" => %{"on" => %{"END_BETTING" => "turn"}},
  iex>        "river" => %{"type" => "final"},
  iex>        "turn" => %{"on" => %{"END_BETTING" => "river"}}
  iex>      }},
  iex>    {"#meditative.p.region1.foo2", nil}
  iex>  ],
  iex>  [{"#meditative.p.region2.bar1", nil}, {"#meditative.p.region2.bar2", nil}]
  iex> ]
  iex> Machine.make_parallel_state_names_from_intermediate_state_representation(xs)
  [["#meditative.p.region1.foo1.flop", "#meditative.p.region1.foo1.river", "#meditative.p.region1.foo1.turn"], [], [], []]
  """
  def make_parallel_state_names_from_intermediate_state_representation(xs) do
    xs
    |> Enum.map(fn xs ->
      xs
      |> Enum.map(fn ({next_state_name, further_nested_states}) ->
        {next_state_name, further_nested_states} # |> Cat.trace("{next_state_name, further_nested_states} in side the map")
        create_parallel_state_names(%{
          "state_name" => next_state_name,
          "child_states" => further_nested_states
        }, true)
      end)
    end)
    |> Enum.flat_map(fn x -> x end)
  end

  def create_parallel_state_names(%{
    "state_name" => state_name,
    "child_states" => child_states
  }, further_nested \\ false) do
    keys = safe_get_keys_of_map(child_states)

    is_invalid_parallel_state?(keys, further_nested)
    |> confirm(fn -> raise "ERROR: You specified #{state_name} to be a parallel state, but did not provide 2 or more sub states for it." end)

    grand_child_states = get_grand_child_states(keys, child_states)
    child_state_names = keys |> Enum.map(fn x -> "#{state_name}.#{x}" end)

    if are_children_states_not_present?(grand_child_states) do
      child_state_names
    else
      combined_state_names = make_parallel_state_name_string_path(grand_child_states, child_state_names) #  |> Cat.trace("WTF is combined_state_names result")
      result =
        make_intermediate_state_representation_from_dsl_with_possible_child_states(grand_child_states, combined_state_names)
        |> make_parallel_state_names_from_intermediate_state_representation()

        [combined_state_names | result]
    end
  end

  # convert_on_done_on_error && create_invoke_map are a quick hack...
  # The issue was that you needed to create the relative state path in relation to the top most level states
  # for the states provided to the invoke map,
  # I know this works for at least first level states that hacve invoke....
  # TODO: Need to ensure that this can work for nested states.
  #       And then parallel states whenever that is gotten to.
  # NOTE: The pattern matches on "#" <> to in the function head are to detect when the user has specified an absolute state string
  #       path in order to transition to an ancestor state rather than a sibling state.
  def convert_on_done_on_error(%{"to" => "#" <> _ = to }, _), do: to
  def convert_on_done_on_error(%{"to" => to } = rest, name), do:
    %{rest | "to" => "#{name |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")}.#{to}"}
  def convert_on_done_on_error("#" <> _ = to, _) when is_binary(to), do: to
  def convert_on_done_on_error(to, name) when is_binary(to), do:
    "#{name |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")}.#{to}"

  def create_invoke_map(nil, _), do: nil
  def create_invoke_map(%{"id" => id, "src" => src, "on_done" => on_done, "on_error" => on_error}, name) do
    converted_on_done = convert_on_done_on_error(on_done, name)
    converted_on_error = convert_on_done_on_error(on_error, name)

    %{
      "id" => id,
      "src" => src,
      "on_done" => converted_on_done,
      "on_error" => converted_on_error
    }
  end

  @doc """
  GOAL: recursively collecting all possible states and nested states into a top level map, where
        each state is indexed with the convention #statechart_id.first_level_state.second_level_state

  # Accessor pattern goes like:
  # states -> "specific_state_name" -> states -> "specific_state_name" -> states -> etc...
  # And it's necessary to keep track of what level we're currently at, so we can store
  # the constructed state under the proper #statechart_id.first_level_state.second_level_state index.

  Should ultimately build up a list of tuples, which will be returned higher up in the callstack,
  where those nested lists of tuples will need to be merged into one list, which then will be used
  to create the final top level map of all possible states in the statechart.
  [[{level_string, constructed_state, transitions}, ...], ...]

  @statechart %{
    "id" => "meditative",
    "initial" => "idle",
    "states" => %{
      "first_step" => %{
        "on" => %{
          "RUN" => "second_step"
        },
        "states" => %{
          "nested_first_step" => %{
            "on" => %{
              "SLIDE" => "to_the_right"
            },
            "states" => %{
              "two_levels_deep_nested_step" => %{
                "on" => %{
                  "SLIDE" => "to_the_left"
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

  states = statechart |> Map.get("states")
  construct_states(states, level)
  # 1. get the keys of all the top level states
  #    - Then create #statechart_id.first_level_state strings <- (which will the level_string in the tuple {level_string, constructed_state}
                                                          and the next state level down will be invoked with construct_states and the level_string)

  Well that went smoothly...
  # NOTE/TODO: having %{"on" => %{"SLIDE" => "to_the_left"}}, in the second tuple position doesn't make sense now that
  # the Transition list is being made.
  [
    {"#meditative.first_step.nested_first_step.two_levels_deep_nested_step",
    %State{
      name: "#meditative.first_step.nested_first_step.two_levels_deep_nested_step",
      on: %{
        "SLIDE" => %Transition{
          event: "SLIDE",
          from: "#meditative.first_step.nested_first_step.two_levels_deep_nested_step",
          to: "#meditative.to_the_left"
        }
      },
      type: nil
    }},
    {"#meditative.first_step.nested_first_step",
    %State{
      name: "#meditative.first_step.nested_first_step",
      on: %{
        "SLIDE" => %Transition{
          event: "SLIDE",
          from: "#meditative.first_step.nested_first_step",
          to: "#meditative.to_the_right"
        }
      },
      type: nil
    }},
    {"#meditative.first_step",
    %State{
      name: "#meditative.first_step",
      on: %{
        "RUN" => %Transition{
          event: "RUN",
          from: "#meditative.first_step",
          to: "#meditative.second_step"
        }
      },
      type: nil
    }},
    {"#meditative.second_step",
    %State{name: "#meditative.second_step", on: nil, type: "final"}}
  ]

  TODO/LLO:
  Now to just get it so that Transitions reflect the proper level keys for from and to states...

  NOTE: This function is recursive, but not tail recursive... But it would be if it weren't for supporting the parallel state feature.
  """
  def construct_states(states, level, acc \\ []) do
    state_names = states |> Cat.maybe ~>> (&Map.keys/1) |> Cat.unwrap

    case state_names do
      nil ->
        acc
      _ ->
        state_names
        |> Enum.map(fn state_name ->
          name = "#{level}.#{state_name}"
          state = states |> get_state_without_sub_states(state_name)
          child_states = states |> get_states_sub_states(state_name)

          transitions = construct_transitions(%{"transitions" => state |> Map.get("on"), "sibling_states" => Utils.safe_get_map_keys(states), "child_states" => Utils.safe_get_map_keys(child_states)}, "#{level}.#{state_name}")
          # transitions |> Cat.trace("how are the transitions constructed?")
          # p: {
          #   type: 'parallel',
          #   states: {
          #     region1 : {
          #       initial: 'foo1',
          #       states: {
          #         foo1: {}
          #         foo2: {}
          #       }
          #     },
          #     region2 : {
          #       initial: 'bar1',
          #       states: {
          #         bar1: {}
          #         bar2: {}
          #       }
          #     }
          #   }

          # %{
          #   "region1" => %{
          #     "initial_state" => "foo1",
          #     "states" => %{
          #       "foo1" => %{"on" => %{"TO_FOO_2" => "foo2"}},
          #       "foo2" => %{"on" => %{"TO_FOO_1" => "foo1"}}
          #     }
          #   },
          #   "region2" => %{
          #     "initial_state" => "bar1",
          #     "states" => %{
          #       "bar1" => %{"on" => %{"TO_BAR_2" => "bar2"}},
          #       "bar2" => %{"on" => %{"TO_BAR_1" => "bar1"}}
          #     }
          #   }
          # }

        # OPTION 2:


        # How I think the states would need to be constructed to facilitate parallel states...

        # OPTION 1:
        # HOWEVER... this won't work, because then you'd need to also create additional Transition structs
            # based on the possible substates of the other parallel states...
        # %State{
        #   # NOTE: all states beneath the first state declared to be "parallel require this flag."
        #   # type: "parallel", ehh... I'll avoid that for now, just gonna support one level of parallel states (thinking
        #   # about supporting recursive parallel states is something else...)
        #   initial_state: nil,
        #   name: ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"],
        #   on: %{
        #     # And of course this is combinatorial... so a list of names of length 3 will have a different
        #     # list of Transition result...
        #     "TO_FOO_2" => [
        #       %Transition{
        #         event: "TO_FOO_2",
        #         from: ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"],
        #         guard: "retries_not_exceeded",
        #         to: ["#meditative.p.region1.foo2", "#meditative.p.region2.bar1"]
        #       },
        #       %Transition{
        #         event: "TO_FOO_2",
        #         from: ["#meditative.p.region1.foo1", "#meditative.p.region2.bar2"],
        #         guard: "retries_not_exceeded",
        #         to: ["#meditative.p.region1.foo2", "#meditative.p.region2.bar2"]
        #       },
        #     ]
        #   }
        # }

        # ["#meditative.p.region1", "#meditative.p.region2"]
        # ["#meditative.p.region1.foo1", "#meditative.p.region2.bar1"]
        # ["#meditative.p.region1.foo1", "#meditative.p.region2.bar2"]
        # ["#meditative.p.region1.foo2", "#meditative.p.region2.bar1"]
        # ["#meditative.p.region1.foo2", "#meditative.p.region2.bar2"]

          # IMMEDIATE TODO (to support parallel states):
          # 1.
          # if type === "parallel", then you need a function that takes %{"state_name" => state, "child_states" => child_states}
          # and creates the State's name list using the child_states name + (the initial_state of any potential child_states that child may have
          #                                                                  and so on for grandchildren recursively)
          # 2.
          # THEN... you need to have a different mode of execution for transactions if it's the case that the current_state is a list...
          # hopefully the refactored transition function is amenable to implementing this change.
          type = state |> Map.get("type")

          # TODO: Use the Either concept... if it's type parallel, put the state in a Left, otherwise, put the state in a Right,
          # Implement separate functions which can be doctested, and provide them as the functions to either/2 for the branching logic.
          if type === "parallel" do
            # TODO: Create a separate function and doctest what the goal of the below line is...
            parallel_state_names = child_states |> Cat.maybe ~>> fn m -> Map.keys(m) end ~>> fn keys -> Enum.map(keys, fn key -> "#{name}.#{key}"end) end |> Cat.unwrap || [name]
            # parallel_state_names # |> Cat.trace("WTF is parallel_state_names")
            create_parallel_state_names(%{
              "state_name" => name,
              "transitions" => transitions,
              "child_states" => child_states
            })
            |> Enum.flat_map(fn x -> x end)
            state = State.new(%{
              "name" => name,
              "on" => transitions,
              "initial_state" => state |> maybe ~>> fn x -> Map.get(x, "initial_state") end ~>> fn x -> "#{level}.#{state_name}.#{x}" end |> Cat.unwrap,
              "on_entry" => state |> Map.get("on_entry"),
              "on_exit" => state |> Map.get("on_exit"),
              "type" => type,
              "parallel_states" => %{
                "parallel_state_names" => parallel_state_names, # TODO/NOTE: Don't think the names created vcia create_parallel_state_names are necessary... ++ names,
                "states" => construct_states(child_states, name, [{name, state} | acc])  |> Utils.to_map
              },
              # "invoke" => state |> Map.get("invoke"), TODO: To be supported after a later refactor.
            })

            [{name, state}]
            # THIS IS IT!!! ALMOST THERE.
            # TODO/LLO:
            # parallel_states: %{
            #   "parallel_state_names" => ["#meditative.p.region1", "#meditative.p.region2",
            #    "#meditative.p.region1.foo1", "#meditative.p.region1.foo2",
            #    "#meditative.p.region2.bar1", "#meditative.p.region2.bar2",
            #    "#meditative.p.region1.foo1.flop", "#meditative.p.region1.foo1.river",
            #    "#meditative.p.region1.foo1.turn"],
            # }
            # ^^ GOT THE DESIRED RESULT....
            # Now, just have to manage transitions while in the parallel state...
            # Could separate out parallel_state_names to be a separate key
            # field on the parallel_states map.... in order to know which potential states to look for
            # under "parallel_states" -> "states" -> "specific_nested_state_of_the_parallel_states"

            # names = ["#meditative.p.region1", "#meditative.p.region2"]
            # names |> Cat.trace("names before construct_states/3")
            # state |> Cat.trace("state before construct_states/3")
            # child_states |> Cat.trace("child_states before construct_states/3")
          else
            state = State.new(%{
              "name" => name,
              "on" => transitions,
              "initial_state" => state |> maybe ~>> fn x -> Map.get(x, "initial_state") end ~>> fn x -> "#{name}.#{x}" end |> Cat.unwrap,
              "on_entry" => state |> Map.get("on_entry"),
              "on_exit" => state |> Map.get("on_exit"),
              "type" => type,
              "invoke" => create_invoke_map(state |> Map.get("invoke"), name),
            })

            # state # |> Cat.trace("state being passed to construct_states/3")
            construct_states(child_states, name, [{name, state} | acc])
          end
        end)
        |> Enum.flat_map(fn x -> x end)
    end
  end

  def interpret(statechart), do: interpret(statechart, %{"actions" => nil, "guards" => nil, "invoke_sources" => nil})
  # opts = %{"actions" => actions, "guards" => guards, "invoke_sources" => invoke_sources})
  def interpret(statechart, opts) do
    # Run the steps necessary to create the State and Transition structs
    # then invoke new to create a new Machine
    id = statechart |> get_id
    states = statechart |> get_constructed_states("##{id}") # <- TODO: grab the invoke key from inside this function?
      # |> Map.get("states")
      # |> construct_states("##{id}")
      # |> Enum.reduce(%{}, fn ({state_name, %State{} = s}, acc) ->
      #   acc |> Map.put(state_name, s)
      # end)

    current_state = "##{id}.#{statechart |> Map.get("initial_state")}"
    current_state_struct = states |> Map.get(current_state)

    # NOTE: This is all nasty...
    parallel_state_key = if (current_state_struct |> Map.get(:type)) === "parallel" do current_state else nil end
    current_state =
      if parallel_state_key !== nil do
        parallel_states = current_state_struct |> Cat.maybe ~>> fn x -> Map.get(x, :parallel_states) end |> Cat.unwrap
        parallel_state_names = parallel_states |> Cat.maybe ~>> fn x -> Map.get(x, "parallel_state_names") end
        # ^^ The result of the above will be a list of the top level parallel states... but you still need to check each of those states for whether
        # they have an initial_state, and set the respective states in the state list accordingly
        parallel_state_names
        ~>> fn xs ->
          xs
          |> Enum.map(fn x ->
            parallel_states
            |> Map.get("states")
            |> Cat.maybe
            ~>> fn parallel_states -> Map.get(parallel_states, x) end
            ~>>
            fn %State{initial_state: initial_state} -> initial_state
              _ -> x
            end
          end)
        end
        |> Cat.unwrap
        |> Enum.map(fn x -> Cat.unwrap(x) end)
      else
        current_state
      end

    new(%{
      "id" => id,
      "current_state" => current_state,
      "parallel_state_key" => parallel_state_key,
      "context" => statechart |> Map.get("context"),
      # "on" => statechart |> Map.get("on"),
      "states" => states,
      "actions" => opts |> Map.get("actions"),
      "guards" => opts |> Map.get("guards"),
      "invoke_sources" => opts |> Map.get("invoke_sources")
    })
  end

  def persist(%__MODULE__{current_state: current_state, context: context, parallel_state_key: parallel_state_key}) do
    %{
      # TODO: Possibly convert the list of parallel states to a string (and then convert the string back into a list in hydrate/3)
      "current_state" => current_state,
      "context" => context,
      "parallel_state_key" => parallel_state_key,
    }
  end
  def persist(_), do: raise("ERROR: Machine.persist/1 must receive a %Machine{} struct as input.")

  @doc """
  persisted_state is a map that consists of:
    - "current_state" (the current finite state of the statechart)
    - "context"
    - "parallel_state_key" (possibly nil)
  """
  def hydrate(
    statechart,
    %{"actions" => actions, "guards" => guards} = opts,
    %{
      "current_state" => current_state,
      "context" => context,
      "parallel_state_key" => parallel_state_key,
    })
  do
    id = statechart |> get_id
    states = statechart |> get_constructed_states("##{id}")

    new(%{
      "id" => id,
      "current_state" => current_state,
      "parallel_state_key" => parallel_state_key,
      # "on" => nil,
      "context" => context,
      "states" => states,
      "actions" => actions,
      "guards" => guards,
      "invoke_sources" => opts |> Map.get("invoke_sources")
    })
  end

  def hydrate(_, _, _), do: raise("ERROR: Machine.hydrate/3 must a map with the keys ['current_state', 'context', 'parallel_state_key'] for it's third argument.")
end
