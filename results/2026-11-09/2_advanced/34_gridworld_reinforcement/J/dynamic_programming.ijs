first_max =: 3 : 'y i.>./y'
bellman =: 4 : 0
    'values gamma state action' =. y
    total =. 0x
    for_transition. >(<state,action){e_transitions x do.
        'cell weight' =. transition
        target =. cell{StateIndex
        future =. 0x
        if. target>:0 do.
            future =. (gamma*target{values)intdiv 100
        end.
        total =. total+weight*((10000*x arrival_reward cell)+future)
    end.
    total intdiv e_denominator x
)
action_values =: 4 : 0
    'values gamma state' =. y
    result =. i.0
    for_action. i.4 do.
        result =. result,x bellman (<values),(<gamma),(<state),<action
    end.
    result
)
greedy_policy =: 4 : 0
    'values gamma' =. y
    result =. i.0
    for_state. i.#States do.
        result =. result,first_max x action_values (<values),(<gamma),<state
    end.
    result
)
value_iteration =: 4 : 0
    'gamma theta' =. y
    values =. (#States)$0x
    changes =. i.0
    delta =. theta+1
    while. delta>theta do.
        updated =. i.0
        for_state. i.#States do.
            updated =. updated,>./x action_values (<values),(<gamma),<state
        end.
        delta =. >./|updated-values
        changes =. changes,delta
        values =. updated
    end.
    (<values),<changes
)
in_place_iteration =: 4 : 0
    'gamma theta' =. y
    values =. (#States)$0x
    sweeps =. 0
    delta =. theta+1
    while. delta>theta do.
        sweeps =. sweeps+1
        delta =. 0
        for_state. i.#States do.
            value =. >./x action_values (<values),(<gamma),<state
            delta =. delta>.|value-state{values
            values =. value state}values
        end.
    end.
    (<values),<sweeps
)
evaluate_policy_value =: 4 : 0
    'policy values gamma theta' =. y
    sweeps =. 0
    delta =. theta+1
    while. delta>theta do.
        sweeps =. sweeps+1
        delta =. 0
        for_state. i.#States do.
            value =. x bellman (<values),(<gamma),(<state),<state{policy
            delta =. delta>.|value-state{values
            values =. value state}values
        end.
    end.
    (<values),<sweeps
)
policy_iteration =: 4 : 0
    'gamma theta' =. y
    policy =. (#States)$0
    values =. (#States)$0x
    rounds =. 0 3$0x
    changed =. 1
    while. changed do.
        'values sweeps' =. x evaluate_policy_value (<policy),(<values),(<gamma),<theta
        improved =. x greedy_policy (<values),<gamma
        changed =. +/policy~:improved
        rounds =. rounds,sweeps,changed,StartState{values
        policy =. improved
    end.
    (<policy),(<values),<rounds
)
