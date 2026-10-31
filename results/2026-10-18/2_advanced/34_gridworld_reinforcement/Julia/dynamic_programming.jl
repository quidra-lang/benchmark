first_max(values) = argmax(values)
function bellman(environment,values,gamma,state,action)
    total = 0
    for (cell,weight) in environment.transitions[state,action]
        target = environment.world.state_index[cell]
        future = target == 0 ? 0 : fld(gamma*values[target],100)
        total += weight*(10000*reward(environment,cell)+future)
    end
    fld(total,environment.slip_total)
end
action_values(environment,values,gamma,state) = [bellman(
    environment,
    values,
    gamma,
    state,
    action
) for action in 1:4]
greedy_policy(environment,values,gamma) = [first_max(action_values(
    environment,
    values,
    gamma,
    state
)) for state in eachindex(values)]
function value_iteration(environment,gamma,theta)
    values = zeros(Int,length(environment.world.states))
    changes = Int[]
    while true
        updated = [maximum(action_values(environment,values,gamma,state)) for state in eachindex(values)]
        change = maximum(abs.(updated.-values))
        push!(changes,change)
        values = updated
        change <= theta && return values,changes
    end
end
function in_place_value_iteration(environment,gamma,theta)
    values = zeros(Int,length(environment.world.states))
    sweeps = 0
    while true
        sweeps += 1
        delta = 0
        for state in eachindex(values)
            value = maximum(action_values(environment,values,gamma,state))
            delta = max(delta,abs(value-values[state]))
            values[state] = value
        end
        delta <= theta && return values,sweeps
    end
end
function evaluate_policy(environment,policy,initial,gamma,theta)
    values = copy(initial)
    sweeps = 0
    while true
        sweeps += 1
        delta = 0
        for (state,action) in enumerate(policy)
            value = bellman(environment,values,gamma,state,action)
            delta = max(delta,abs(value-values[state]))
            values[state] = value
        end
        delta <= theta && return values,sweeps
    end
end
function policy_iteration(environment,gamma,theta)
    policy = ones(Int,length(environment.world.states))
    values = zeros(Int,length(policy))
    rounds = Tuple{Int,Int,Int}[]
    while true
        values,sweeps = evaluate_policy(environment,policy,values,gamma,theta)
        improved = greedy_policy(environment,values,gamma)
        changes = count(improved .!= policy)
        push!(rounds,(sweeps,changes,values[environment.world.start_state]))
        policy = improved
        changes == 0 && return policy,values,rounds
    end
end
