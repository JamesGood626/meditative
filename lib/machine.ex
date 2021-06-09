defmodule Machine do

  import Cat
  alias State
  alias Transition

  defstruct [:id, :current_state, :parallel_state_key, :context, :on, :states, :actions, :guards]

  def get_id(statechart) do
    statechart
    |> Map.get("id")
    |> Cat.to_either("You must provide an id to the statechart")
    |> Cat.either(fn msg -> raise msg end, fn val -> val end)
    |> Cat.unwrap
  end

  def get_constructed_states(statechart, id) do
    statechart
    |> Cat.maybe
    ~>> fn x -> Map.get(x, "states") end
    ~>> fn x -> construct_states(x, id) end
    ~>> fn x ->
          Enum.reduce(x, %{}, fn ({state_name, %State{} = s}, acc) ->
          acc |> Map.put(state_name, s)
        end)
      end
    |> Cat.unwrap
  end

  def get_state_without_sub_states(states, state_name) do
    states
    |> Cat.maybe
    ~>> fn x -> x |> Map.get(state_name) end
    ~>> fn x -> x |> Map.delete("states") end
    |> Cat.unwrap
  end

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
    ~>> fn x -> Map.get(x, :to) end
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

  def get_action_function(machine, action) do
    machine
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :actions) end
    ~>> fn x -> Map.get(x, action) end
    |> Cat.unwrap
  end

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
    "machine" => machine,
    "context" => context
  }) do
    state
    |> Cat.maybe
    ~>> fn x -> Map.get(x, :on) end
    ~>> fn x -> Map.get(x, get_event(event)) end
    ~>> fn xs when is_list(xs) ->
            xs
            |> Enum.find(fn (%Transition{guard: guard} = transition) -> run_cond(%{"machine" => machine, "guard" => guard, "context" => context})
                              x -> x
                          end)
           x -> x
        end
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

  def apply_actions(%{
    "actions" => nil,
    "context" => context
  }) do
    {nil, context}
  end

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

  def run_on_exit(%{"state" => state, "actions" => actions, "machine" => machine, "context" => context,  "event" => event}) do
    state
    |> get_on_exit
    |> Utils.to_list
    |> Enum.reduce(context, fn (action, updated_context) ->
      invoke_action(%{"machine" => machine, "action" => action, "context" => updated_context, "event" => event}) |> IO.inspect
    end)
  end

  def run_on_entry(%{"state" => state, "actions" => actions, "machine" => machine, "context" => context,  "event" => event}) do
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
    target_state = transition |> get_target_state |> get_state(states)
    case {transition, run_cond(%{"machine" => machine, "guard" => get_guard(transition), "context" => context})} do
      {%Transition{to: to, actions: actions}, true} ->
        {_, new_context} = apply_actions(%{
          "machine" => machine,
          "actions" => actions,
          "context" => context,
          "event" => event
        })
        # Return an updated Machine Struct with updated finite and context state.
        new_context = run_on_exit(%{"state" => state, "actions" => actions, "machine" => machine, "context" => new_context, "event" => event})
        new_context = run_on_entry(%{"state" => target_state, "actions" => actions, "machine" => machine, "context" => new_context, "event" => event})
        %{"new_context" => new_context, "to" => to}
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
    "target_state" => target_state,
    "cond_result" => cond_result,
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
    "transition" => %Transition{to: nil, actions: actions} = transition,
    "cond_result" => true
  }) do
    {"RUN_ACTIONS", transition}
  end

  def determine_next_transition_step(%{
    "transition" => %Transition{to: to, actions: actions} = transition,
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
  def parallel_state_transition(%Machine{current_state: current_state, parallel_state_key: parallel_state_key, states: states, context: context, guards: guards} = machine, event) do
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

  def handle_transition(%{
    "next_step" => next_step,
    "transition" => transition,
    "machine" => machine,
    "context" => context,
    "event" => event,
    "states" => states,
    "from_state" => from_state,
    "target_state" => target_state,
  }) do
    case next_step do
      {"TRANSITION", %Transition{to: to, actions: actions}} ->
        # TODO: Had to pattern match on the tuple after adding the actions can return a tuple to trigger a transition feature...
        #       would be better if I create a function that only retrieves a new_context back if it's a regular transition we're executing
        #       otherwise get a tuple back if it's the actions feature.
        {_, new_context} = apply_actions(%{
          "machine" => machine,
          "actions" => actions,
          "context" => context,
          "event" => event
        })
        # Return an updated Machine Struct with updated finite and context state.
        new_context = run_on_exit(%{"state" => from_state, "actions" => actions, "machine" => machine, "context" => new_context,  "event" => event})
        new_context = run_on_entry(%{"state" => target_state, "actions" => actions, "machine" => machine, "context" => new_context,  "event" => event})
        transient_transition = target_state |> get_transition_associated_with_event(%{
          "event" => "",
          "machine" => machine,
          "context" => context
        })
      %{"new_context" => new_context, "to" => to} =
            apply_transient_transition(%{"machine" => machine, "transition" => transient_transition, "context" => new_context, "event" => event, "states" => states, "state" => from_state, "fallback_to" => to})
        %{machine | current_state: target_state |> Cat.maybe ~>> fn x -> Map.get(x, :initial_state) end |> Cat.unwrap || to, context: new_context}
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
            # LLO/WTF
            Machine.transition(updated_machine, transition_event)
        end
      "NO_TRANSITION" ->
        machine
      {"UNEXPECTED_ERROR", x} ->
        IO.inspect(x)
        raise "UNEXPECTED ERROR: in Machine.transition/2"
    end
  end

  # TODO:
  # event can be either a string or a map which stores the string under the key :type + any arbitrary key the user wants to use
  # to establish some kind of additional metadata for the transition.
  def transition(%Machine{current_state: current_state, states: states, context: context, guards: guards} = machine, event) do
    # 1. Retrieve current_state from machine
    # current_state = machine |> Map.get("current_state") |> IO.inspect
    #   1a.
    #      2a. Check if the current_state is a parallel state... (if it's a list)
    #          If so, then run the steps in the moduledoc of the Machine module.
    #   1b.
    #       2b. retrieve the corresponding current_state Struct from the states list
    #       IO.puts("THE MACHINE IN TRANSITION/2")
    #       IO.inspect(machine)
    if is_list(current_state) do
      # transition parallel state...
      case parallel_state_transition(machine, event) do # |> Cat.trace("Result of parallel_state_transition")
        {idx, from, %Transition{to: to} = transition} ->
          parallel_state_key = machine |> Map.get(:parallel_state_key)
          if parallel_state_key === nil do raise "OPEN SOURCE DEVELOPER ERROR: If state is in a parallel configuration, then :parallel_state_key on %Machine{} should never be nil!!!" end
          parallel_states = machine |> Map.get(:states) |> Map.get(parallel_state_key) |> Map.get(:parallel_states) |> Map.get("states")
          from_state = parallel_states |> Cat.maybe ~>> fn x -> Map.get(x, current_state |> Enum.at(idx)) end |> Cat.unwrap # |> Cat.trace("what is state...")
          # transition |> Cat.trace("transition in the pattern match on parallel_state_transition(machine, event)")

          # NOTE: Implement something better than this... the part the follows after || is meant to handle cases where we're transitioning
          #       out of the parallel state configuration.
          target_state = transition |> get_target_state |> get_state(parallel_states) || transition |> get_target_state |> get_state(states) # |> Cat.trace("target_state result")
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
          if to in possible_parallel_states do
            # A transition into a parallel state
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
            %{updated_machine | current_state: List.update_at(current_state, idx, fn _ -> to end)}
          else
            # A transition out of the parallel state
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
            %{updated_machine | parallel_state_key: nil}
          end
        machine ->
          machine
      end
    else
      from_state = states |> Cat.maybe ~>> fn x -> Map.get(x, current_state) end |> Cat.unwrap
      # global_transition = machine |> get_transition_associated_with_event(%{
      #   "event" => event,
      #   "machine" => machine,
      #   "context" => context
      # })
      transition = from_state |> get_transition_associated_with_event(%{
        "event" => event,
        "machine" => machine,
        "context" => context
      })

      # TESTING/TODO
      # if global_transition !== nil && transition !== nil do
      #   raise "DEVELOPER ERROR: You may not have transitions with the same name on the global 'on' transitions map and in \
      #          a specific finite state's 'on' transition map. event: #{event} current_state: #{current_state}"
      # end
      target_state = transition |> get_target_state |> get_state(states)
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
      # |> Cat.to_either("ERROR: Attempted to transition to the state: #{get_target_state(transition)}, that is not declared on the statechart!")
      # |> Cat.either(fn msg -> raise msg end, &Cat.id/1)
      # |> Cat.unwrap
    end
  end

  def new(%{
    # "initial_state" => initial_state,
    "id" => id,
    "current_state" => current_state,
    "context" => context,
    # "on" => on,
    "states" => states,
    "actions" => actions,
    "guards" => guards
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

  @doc """
  Strive to have unique names for top level states and child states in the statechart... otherwise I'll need to rewrite this code.

  EXAMPLE USAGE:
  get_target_state_name(%{"to" => "nested_first_step", "state_name" => state_name, "sibling_states" => ["first_step", "second_step"], "child_states" => ["nested_first_step", "to_the_right"]})
  => "#meditative.first_step.nested_first_step"
  %{
    "RUN" => %Transition{
      actions: "increment",
      event: "RUN",
      from: "#meditative.first_step",
      to: "#meditative.first_step.nested_first_step"
    }
  }

  # THIS was the state transition that I noticed was a problem, because I was outputting "#meditative.first_step.nested_first_step.to_the_right" instead (TODO: update older docs that showed a transition to of the string to the left)
  get_target_state_name(%{"to" => "to_the_right", "state_name" => state_name, "sibling_states" => ["nested_first_step", "to_the_right"], "child_states" => ["to_the_left", "two_levels_deep_nested_step"]})
  %{
    "SLIDE" => %Transition{
      actions: nil,
      event: "SLIDE",
      from: "#meditative.first_step.nested_first_step",
      to: "#meditative.first_step.to_the_right"
    }
  }
  """
  # def get_target_state_name(%{"to" => xs, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}) when is_list(xs) do
  #   xs
  #   |> Enum.map(fn to ->
  #     get_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states})
  #   end)
  # end

  def get_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}) do
    # IMMEDIATE TODO: Zenith was failing to start due to "to" being nil when String.at was called...
    # Need to refine this so that whatever the statechart interprets doesn't crash...
    if to !== nil && String.at(to, 0) === "#" do
      # NOTE: This is to ensure that we have a path from #statechart_id.nested_state
      to
    else
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
  end

  @doc """
  iex(5)> s |> String.split(".") |> Enum.slice(0, 2)
  ["#meditative", "first_step"]
  iex(6)> s |> String.split(".") |> Enum.slice(0, 1)
  ["#meditative"]
  """
  def construct_transitions(nil, _), do: nil
  def construct_transitions(%{"transitions" => transitions, "sibling_states" => sibling_states, "child_states" => child_states}, state_name) do
    events = transitions |> Cat.maybe ~>> fn x -> Map.keys(x) end |> Cat.unwrap |> Utils.safe_list
    events
    |> Enum.reduce(%{}, fn (event, acc) ->
      dsl_transitions = transitions |> Map.get(event) |> extract_transition
      # NOTE: cases required to support an event having an array of transitions...
      case dsl_transitions do
        {to, rest} ->
          transition = Transition.new(%{
            "event" => event,
            "from" => state_name,
            "to" => get_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}),
            "actions" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "actions") end |> Cat.unwrap,
            "guard" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "guard") end |> Cat.unwrap
          })
          # TODO: would be nice if I could curry the Map.put with event...
          acc |> Map.put(event, transition)
        xs ->
        transitions =
          xs
          |> Enum.map(fn {to, rest} ->
            Transition.new(%{
              "event" => event,
              "from" => state_name,
              "to" => get_target_state_name(%{"to" => to, "state_name" => state_name, "sibling_states" => sibling_states, "child_states" => child_states}),
              "actions" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "actions") end |> Cat.unwrap,
              "guard" => rest |> Cat.maybe ~>> fn x -> Map.get(x, "guard") end |> Cat.unwrap
            })
          end)
        acc |> Map.put(event, transitions)
      end
    end)
  end

  def create_parallel_state_names(%{
    "state_name" => state_name,
    "child_states" => child_states
  }, further_nested \\ false) do
    keys = child_states |> Cat.maybe ~>> fn x -> Map.keys(x) end |> Cat.unwrap || []

    if further_nested do child_states end
    if keys |> length < 2 && (not further_nested) do
      raise "ERROR: You specified #{state_name} to be a parallel state, but did not provide 2 or more sub states for it."
    else
      grand_child_states =
        keys
        |> Enum.map(fn x ->
          child_states
          |> Cat.maybe
          ~>> fn y -> Map.get(y, x) end
          ~>> fn y -> Map.get(y, "states") end
          |> Cat.unwrap
        end)

        # IMMEDIATE LLO:
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

        # NOTE: How will the transition names be handled?... for example "TOO_FOO_2"'s "foo2", should we be appending it with the child_state "#meditative.p.region1" name?
        #       or will the construct_transition function handle creating the appropriate state path?
      child_state_names = keys |> Enum.map(fn x -> "#{state_name}.#{x}" end)

      if grand_child_states |> Enum.all?(fn x -> x === nil end) do
        child_state_names
      else
        combined_state_names =
          grand_child_states
          |> Enum.with_index
          |> Enum.map(fn ({m, idx}) ->
                child_state_name = child_state_names |> Enum.at(idx)
                m |> Map.keys |> Enum.map(fn x -> "#{child_state_name}.#{x}" end)
              end)
          |> Enum.flat_map(fn x -> x end)

        # if (further_nested) do combined_state_names |> Cat.trace("nested combined_state_names") end

        result =
          grand_child_states
          |> Enum.with_index
          |> Enum.map(fn ({m, idx}) ->
              m
              |> Cat.maybe
              ~>> fn x -> Map.keys(x) end
              ~>> (fn keys -> keys |> Enum.map(fn key -> m |> Map.get(key) end) end)
              ~>> (fn xs ->
                  xs
                  |> Enum.map(fn %{"states" => states} -> {combined_state_names |> Enum.at(idx), states}
                                _ -> {combined_state_names |> Enum.at(idx), nil}
                  end)
                end)
              |> Cat.unwrap
            end)
          # |> Cat.trace("RESULT OF {next_state_name, further_nested_states}")
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
          # |> Cat.trace("RESULT OF further_nested create_parallel_state_names")

          [combined_state_names | result]
      end
    end
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
          if type === "parallel" do
            # para
            parallel_state_names = child_states |> Cat.maybe ~>> fn m -> Map.keys(m) end ~>> fn keys -> Enum.map(keys, fn key -> "#{name}.#{key}"end) end |> Cat.unwrap || [name]
            parallel_state_names # |> Cat.trace("WTF is parallel_state_names")
            names = create_parallel_state_names(%{
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
                "parallel_state_names" => parallel_state_names, # TODO/NOTE: Don't thinmkl the names created vcia create_parallel_state_names are necessary... ++ names,
                "states" => construct_states(child_states, name, [{name, state} | acc])  |> Utils.to_map
              }
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
              "type" => type
            })

            state # |> Cat.trace("state being passed to construct_states/3")
            construct_states(child_states, name, [{name, state} | acc])
          end
        end)
        |> Enum.flat_map(fn x -> x end)
    end
  end

  def interpret(statechart), do: interpret(statechart, %{"actions" => nil, "guards" => nil})
  def interpret(statechart, %{"actions" => actions, "guards" => guards}) do
    # Run the steps necessary to create the State and Transition structs
    # then invoke new to create a new Machine
    id = statechart |> get_id
    states = statechart |> get_constructed_states("##{id}")
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
      "actions" => actions,
      "guards" => guards
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
    %{"actions" => actions, "guards" => guards},
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
      "guards" => guards
    })
  end

  def hydrate(_, _, _), do: raise("ERROR: Machine.hydrate/3 must a map with the keys ['current_state', 'context', 'parallel_state_key'] for it's third argument.")
end
