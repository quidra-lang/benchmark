include("environment.jl")
include("dynamic_programming.jl")
include("td_learning.jl")
include("monte_carlo.jl")
include("report.jl")

const METHODS = ("mc","sarsa","q_learning","expected_sarsa","dyna_q")
const POLICY_NAMES = ("value_iteration","policy_iteration",METHODS...)
const ENDINGS = ("goal","pit","timeout")
const ABSORPTION_UNIT = 100000000
pairs_of(values) = [(values[i],values[i+1]) for i in 1:2:length(values)]
function read_settings(path)
    fields = Dict{String,Vector{Int}}()
    for line in readlines(path)
        parts = split(line)
        fields[parts[1]] = parse.(Int,parts[2:end])
    end
    (
        gamma=only(fields["GAMMA"]),step_reward=only(fields["STEP_REWARD"]),
        slip_total=fields["SLIP"][1],floor_slip=fields["SLIP"][2],ice_slip=fields["SLIP"][3],
        theta=only(fields["THETA"]),gamma_sweep=fields["GAMMA_SWEEP"],slip_sweep=pairs_of(fields["SLIP_SWEEP"]),
        episodes=only(fields["EPISODES"]),step_limit=only(fields["STEP_LIMIT"]),block_size=only(fields["BLOCK_SIZE"]),
        alpha_schedule=pairs_of(fields["ALPHA"]),epsilon_schedule=pairs_of(fields["EPSILON"]),
        planning_steps=only(fields["PLANNING_STEPS"]),seed=only(fields["SEED"]),
        rollouts=only(fields["ROLLOUTS"]),rollout_seed=only(fields["ROLLOUT_SEED"])
    )
end
schedule_value(schedule,episode) = last([number for (start,number) in schedule if start <= episode])
function phase_ranges(settings)
    starts = sort(unique([start for (start,_) in vcat(settings.alpha_schedule,settings.epsilon_schedule)]))
    collect(zip(starts,vcat(starts[2:end].-1,[settings.episodes])))
end
count_agreements(first,second) = count(first .== second)
ending_counts(endings) = [count(==(ending),endings) for ending in ENDINGS]
policy_of(q) = [first_max(@view q[state,:]) for state in axes(q,1)]
state_visits(learner) = vec(sum(learner.visits,dims=2))
value_errors(q,optimal) = [abs(maximum(@view q[state,:])-optimal[state]) for state in eachindex(optimal)]
function learn(method,environment,settings,optimal_values,optimal_policy)
    world = environment.world
    count = length(world.states)
    generator = RandomGenerator(settings.seed)
    q,visits = zeros(Int,count,4),zeros(Int,count,4)
    model,averages = DynaModel(count),ReturnAverages(count)
    episodes,blocks = NamedTuple[],Tuple{Int,Int,Int}[]
    for number in 1:settings.episodes
        alpha = schedule_value(settings.alpha_schedule,number)
        epsilon = schedule_value(settings.epsilon_schedule,number)
        state = world.start_state
        total,steps,ending = 0,0,"timeout"
        cells = [world.start]
        history = Tuple{Int,Int,Int}[]
        action = method == "sarsa" ? choose!(generator,@view(q[state,:]),epsilon) : 1
        while steps < settings.step_limit
            method != "sarsa" && (action=choose!(generator,@view(q[state,:]),epsilon))
            cell,r = step!(environment,generator,state,action)
            visits[state,action] += 1
            total += r
            steps += 1
            push!(cells,cell)
            next_state = world.state_index[cell]
            terminal = next_state == 0
            if method == "mc"
                push!(history,(state,action,r))
            elseif method == "sarsa"
                next_action = terminal ? action : choose!(generator,@view(q[next_state,:]),epsilon)
                next_value = terminal ? 0 : q[next_state,next_action]
                td_update!(q,state,action,td_target(r,terminal,next_value,settings.gamma),alpha)
                action = next_action
            else
                next_value = terminal ? 0 : method == "expected_sarsa" ? expected_value(
                    @view(q[next_state,:]),
                    epsilon
                ) : maximum(@view q[next_state,:])
                td_update!(q,state,action,td_target(r,terminal,next_value,settings.gamma),alpha)
                if method == "dyna_q"
                    record!(model,state,action,r,next_state)
                    plan!(model,generator,q,settings.gamma,alpha,settings.planning_steps)
                end
            end
            if terminal
                ending = terminal_name(world,cell)
                break
            end
            state = next_state
        end
        method == "mc" && update!(averages,q,history,settings.gamma)
        push!(episodes,(total=total,steps=steps,ending=ending,cells=cells))
        if number%settings.block_size == 0
            agree = count_agreements(policy_of(q),optimal_policy)
            error = fld(sum(value_errors(q,optimal_values)),count)
            coverage = sum(sum(@view visits[state,:]) > 0 for state in 1:count)
            push!(blocks,(agree,error,coverage))
        end
    end
    (method=method,q=q,visits=visits,episodes=episodes,blocks=blocks)
end
function nominal_path(environment,policy,origin,limit)
    world = environment.world
    cells = [origin]
    while true
        state = world.state_index[last(cells)]
        target = environment.moves[state,policy[state]]
        repeated = target in cells
        push!(cells,target)
        is_terminal(world,target) && return terminal_name(world,target),cells
        repeated && return "loop",cells
        length(cells)-1 == limit && return "limit",cells
    end
end
function basin_symbols(environment,policy,limit)
    world = environment.world
    symbols = String[]
    for cell in world.states
        ending,cells = nominal_path(environment,policy,cell,limit)
        push!(
            symbols,
            ending in ("goal","pit") ? string(Char(Int('a')+world.terminal_index[last(cells)]-1)) : "*"
        )
    end
    symbols
end
function risky_states(environment,policy)
    sum(any(environment.world.kinds[cell] == 'P' for (cell,_) in environment.transitions[state,action]) for (
        state,
        action
    ) in enumerate(policy))
end
function distances(environment)
    world = environment.world
    distance = fill(-1,length(world.kinds))
    distance[world.start] = 0
    queue = [world.start]
    index = 1
    while index <= length(queue)
        cell = queue[index]
        index += 1
        state = world.state_index[cell]
        for action in 1:4, (target,_) in environment.transitions[state,action]
            if distance[target] == -1
                distance[target] = distance[cell]+1
                !is_terminal(world,target) && push!(queue,target)
            end
        end
    end
    distance
end
function symmetry(world,values,policy)
    pairs,equal,mirrored = 0,0,0
    for (state,cell) in enumerate(world.states)
        row,col = divrem(cell-1,world.cols)
        mirror_col = world.cols-1-col
        other = world.state_index[row*world.cols+mirror_col+1]
        if col < mirror_col && other != 0
            pairs += 1
            equal += values[state] == values[other]
            mirrored += policy[other] == (1,4,3,2)[policy[state]]
        end
    end
    pairs,equal,mirrored
end
function absorption(environment,policy,limit)
    world = environment.world
    goal,pit,expected = zeros(Int,length(policy)),zeros(Int,length(policy)),zeros(Int,length(policy))
    for _ in 1:limit
        next_goal,next_pit,next_expected = similar(goal),similar(pit),similar(expected)
        for (state,action) in enumerate(policy)
            gt,pt,et = 0,0,0
            for (cell,weight) in environment.transitions[state,action]
                target = world.state_index[cell]
                if target != 0
                    gt += weight*goal[target]
                    pt += weight*pit[target]
                    et += weight*expected[target]
                elseif world.kinds[cell] == 'G'
                    gt += weight*ABSORPTION_UNIT
                else
                    pt += weight*ABSORPTION_UNIT
                end
            end
            next_goal[state] = fld(gt,environment.slip_total)
            next_pit[state] = fld(pt,environment.slip_total)
            next_expected[state] = ABSORPTION_UNIT+fld(et,environment.slip_total)
        end
        goal,pit,expected = next_goal,next_pit,next_expected
    end
    start = world.start_state
    goal[start],pit[start],expected[start]
end
function behaviour_value(environment,policy,epsilon,gamma,theta)
    values = zeros(Int,length(policy))
    sweeps = 0
    while true
        sweeps += 1
        delta = 0
        for (state,chosen) in enumerate(policy)
            backups = action_values(environment,values,gamma,state)
            total = sum((epsilon+(action == chosen ? 4*(1000-epsilon) : 0))*backups[action] for action in 1:4)
            value = fld(total,4000)
            delta = max(delta,abs(value-values[state]))
            values[state] = value
        end
        delta <= theta && return values[environment.world.start_state],sweeps
    end
end
function perform_rollouts(environment,policy,settings)
    world = environment.world
    generator = RandomGenerator(settings.rollout_seed)
    returns,discounted,steps,endings = Int[],Int[],Int[],String[]
    terminals = zeros(Int,length(world.terminals))
    for _ in 1:settings.rollouts
        state = world.start_state
        rewards = Int[]
        ending = "timeout"
        while length(rewards) < settings.step_limit
            cell,r = step!(environment,generator,state,policy[state])
            push!(rewards,r)
            state = world.state_index[cell]
            if state == 0
                ending = terminal_name(world,cell)
                terminals[world.terminal_index[cell]] += 1
                break
            end
        end
        push!(returns,sum(rewards))
        push!(discounted,discounted_return(rewards,settings.gamma))
        push!(steps,length(rewards))
        push!(endings,ending)
    end
    (returns=returns,discounted=discounted,steps=steps,endings=endings,terminals=terminals)
end
function evaluate_one(environment,policy,settings,optimal_values,optimal_policy,optimal_actions)
    values,sweeps = evaluate_policy(
        environment,
        policy,
        zeros(Int,length(policy)),
        settings.gamma,
        settings.theta
    )
    gaps = optimal_values.-values
    improved = greedy_policy(environment,values,settings.gamma)
    improved_values,_ = evaluate_policy(
        environment,
        improved,
        zeros(Int,length(policy)),
        settings.gamma,
        settings.theta
    )
    (
        values=values,sweeps=sweeps,agree=count_agreements(policy,optimal_policy),
        optimal_actions=sum(policy[state] in optimal_actions[state] for state in eachindex(policy)),
        max_gap=maximum(gaps),gap_state=argmax(gaps),improved_changes=count(improved .!= policy),
        improved_start=improved_values[environment.world.start_state],improved_agree=count_agreements(
            improved,
            optimal_policy
        ),
        absorption=absorption(
            environment,
            policy,
            settings.step_limit
        ),rollouts=perform_rollouts(environment,policy,settings)
    )
end
function sensitivity_text(environment,gamma,settings,optimal_policy)
    world = environment.world
    values,changes = value_iteration(environment,gamma,settings.theta)
    policy = greedy_policy(environment,values,gamma)
    ending,cells = nominal_path(environment,policy,world.start,settings.step_limit)
    "iterations $(length(changes)) value_start $(fixed_text(values[world.start_state])) path $ending steps $(length(cells)-1) last $(cell_text(world,last(cells))) differences $(count(policy .!= optimal_policy))"
end
function values_report(
    world,
    settings,
    environment,
    values,
    changes,
    q,
    optimal_policy,
    optimal_actions,
    in_place_sweeps,
    iteration_policy,
    iteration_values,
    rounds
)
    state_text(state) = cell_text(world,world.states[state])
    n = length(world.states)
    distance = distances(environment)
    summary = [
        "world rows $(world.rows) cols $(world.cols) states $n walls $(count(==('#'),world.kinds)) floor $(count(kind->kind in ('.','S'),world.kinds)) ice $(count(==('~'),world.kinds)) goals $(count(==('G'),world.kinds)) pits $(count(==('P'),world.kinds))",
        "start $(cell_text(world,world.start)) reachable $(count(cell->distance[cell] != -1,world.states))"
    ]
    for (index,cell) in enumerate(world.terminals)
        steps = distance[cell] == -1 ? "-" : string(distance[cell])
        push!(
            summary,
            "terminal $(cell_text(world,cell)) $(terminal_name(world,cell)) reward $(world.rewards[index]) distance $steps"
        )
    end
    vi = ["value_iteration gamma $(settings.gamma) theta $(fixed_text(settings.theta)) iterations $(length(changes))"]
    append!(
        vi,
        ["iteration $number max_change $(fixed_text(change))" for (number,change) in enumerate(changes)]
    )
    tied = findall(actions->length(actions) > 1,optimal_actions)
    ties = ["ties $(length(tied))"]
    for state in tied
        letters = join(ACTION_LETTERS[action] for action in optimal_actions[state])
        push!(ties,"tie $(state_text(state)) $letters")
    end
    pairs,equal,mirrored = symmetry(world,values,optimal_policy)
    push!(ties,"symmetry pairs $pairs equal_values $equal mirrored_actions $mirrored")
    pi = ["policy_iteration rounds $(length(rounds))"]
    for (number,(sweeps,changed,start_value)) in enumerate(rounds)
        push!(pi,"round $number sweeps $sweeps changed $changed value_start $(fixed_text(start_value))")
    end
    differences = abs.(iteration_values.-values)
    comparison = [
        "comparison policy_differences $(count(iteration_policy .!= optimal_policy)) max_value_difference $(fixed_text(maximum(differences))) at $(state_text(argmax(differences)))",
        "backups value_iteration $(length(changes)*n*4) in_place_iterations $in_place_sweeps in_place $(in_place_sweeps*n*4) policy_iteration $(sum(first,rounds)*n+length(rounds)*n*4)"
    ]
    gamma_sweep = ["gamma_sweep"]
    for gamma in settings.gamma_sweep
        push!(gamma_sweep,"gamma $gamma "*sensitivity_text(environment,gamma,settings,optimal_policy))
    end
    slip_sweep = ["slip_sweep"]
    for (floor_slip,ice_slip) in settings.slip_sweep
        altered = Environment(world,settings.step_reward,settings.slip_total,floor_slip,ice_slip)
        push!(
            slip_sweep,
            "slip $floor_slip $ice_slip "*sensitivity_text(altered,settings.gamma,settings,optimal_policy)
        )
    end
    join_parts([
        summary,vi,vcat(["optimal_values"],value_grid(world,values)),
        vcat(["optimal_action_counts"],symbol_grid(world,string.(length.(optimal_actions)))),ties,pi,
        vcat(["policy_iteration_values"],value_grid(world,iteration_values)),comparison,gamma_sweep,slip_sweep
    ])
end
function policies_report(world,settings,environment,policies,learners)
    parts = Vector{String}[]
    for (index,(name,policy)) in enumerate(zip(POLICY_NAMES,policies))
        ending,cells = nominal_path(environment,policy,world.start,settings.step_limit)
        counts = [count(==(action),policy) for action in 1:4]
        lines = vcat([name],policy_grid(world,policy),[
            "path $ending steps $(length(cells)-1) $(cells_text(world,cells))",
            "actions N $(counts[1]) E $(counts[2]) S $(counts[3]) W $(counts[4]) risk $(risky_states(environment,policy))",
            "basins"
        ],symbol_grid(world,basin_symbols(environment,policy,settings.step_limit)))
        if index >= 3
            totals = state_visits(learners[index-2])
            digits = [total == 0 ? "0" : string(length(string(total))) for total in totals]
            append!(lines,vcat(["visits"],symbol_grid(world,digits)))
        end
        push!(parts,lines)
    end
    join_parts(parts)
end
block_episodes(learner,number,size) = learner.episodes[((number-1)*size+1):(number*size)]
function learning_curves(learners,settings)
    lines = ["method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"]
    for learner in learners, (number,(agree,error,coverage)) in enumerate(learner.blocks)
        episodes = block_episodes(learner,number,settings.block_size)
        counts = ending_counts([episode.ending for episode in episodes])
        fields = (
            learner.method,
            number,
            average_text(sum(e.total for e in episodes),settings.block_size),
            average_text(sum(e.steps for e in episodes),settings.block_size),
            counts...,
            agree,
            fixed_text(error),
            coverage
        )
        push!(lines,join(fields,','))
    end
    lines
end
function evaluation_report(world,settings,environment,optimal_values,optimal_q,policies,learners,evaluations)
    n,start = length(world.states),world.start_state
    state_text(state) = cell_text(world,world.states[state])
    parts = Vector{String}[]
    push!(
        parts,
        ["summary states $n start $(cell_text(world,world.start)) rollouts $(settings.rollouts) step_limit $(settings.step_limit)"]
    )
    policy_values = ["policies","policy agree optimal_actions value_start sweeps max_gap at"]
    improvement = ["improvement","policy changed value_start agree"]
    absorption_lines = ["absorption","policy p_goal p_pit p_timeout expected_steps"]
    rollout_lines = [
        "rollouts",
        "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"
    ]
    terminals = ["terminals","policy "*cells_text(world,world.terminals)]
    for (name,evaluation) in zip(POLICY_NAMES,evaluations)
        push!(
            policy_values,
            "$name $(evaluation.agree) $(evaluation.optimal_actions) $(fixed_text(evaluation.values[start])) $(evaluation.sweeps) $(fixed_text(evaluation.max_gap)) $(state_text(evaluation.gap_state))"
        )
        push!(
            improvement,
            "$name $(evaluation.improved_changes) $(fixed_text(evaluation.improved_start)) $(evaluation.improved_agree)"
        )
        goal,pit,expected = evaluation.absorption
        fields = [fixed_text(fld(value,10000)) for value in (goal,pit,ABSORPTION_UNIT-goal-pit,expected)]
        push!(absorption_lines,"$name "*join(fields,' '))
        summary = evaluation.rollouts
        returns = sort(summary.returns)
        fields = (
            name,
            average_text(sum(summary.returns),settings.rollouts),
            fixed_text(fld(sum(summary.discounted),settings.rollouts)),
            average_text(sum(summary.steps),settings.rollouts),
            ending_counts(summary.endings)...,
            first(returns),
            returns[(settings.rollouts+1)÷2],
            last(returns)
        )
        push!(rollout_lines,join(fields,' '))
        push!(terminals,"$name "*join(summary.terminals,' '))
    end
    append!(parts,[policy_values,improvement,absorption_lines])
    behaviour = ["behaviour","method epsilon value_start sweeps"]
    q_errors = ["q_errors","method mean_abs max_abs at unvisited tied"]
    q_action_errors = ["q_action_errors","method N E S W"]
    training = ["training","method steps goals pits timeouts best_block best_mean last_mean reach"]
    visited = ["visited"]
    last_episodes = ["last_episodes"]
    phases = ["phases"]
    epsilon = schedule_value(settings.epsilon_schedule,settings.episodes)
    optimal_total = sum(evaluations[1].rollouts.returns)
    for learner in learners
        name = learner.method
        policy = policy_of(learner.q)
        value,sweeps = behaviour_value(environment,policy,epsilon,settings.gamma,settings.theta)
        push!(behaviour,"$name $epsilon $(fixed_text(value)) $sweeps")
        errors = value_errors(learner.q,optimal_values)
        totals = state_visits(learner)
        tied = sum(count(==(maximum(@view learner.q[state,:])),@view learner.q[state,:]) > 1 for state in 1:n)
        push!(
            q_errors,
            "$name $(fixed_text(fld(sum(errors),n))) $(fixed_text(maximum(errors))) $(state_text(argmax(errors))) $(count(==(0),totals)) $tied"
        )
        fields = [name]
        for action in 1:4
            states = findall(>(0),learner.visits[:,action])
            total = sum(abs(learner.q[state,action]-optimal_q[state,action]) for state in states;init=0)
            push!(fields,isempty(states) ? "-" : fixed_text(fld(total,length(states))))
        end
        push!(q_action_errors,join(fields,' '))
        block_returns = [sum(e.total for e in block_episodes(
            learner,
            number,
            settings.block_size
        )) for number in eachindex(learner.blocks)]
        best = argmax(block_returns)
        reach = findfirst(
            total->10*settings.rollouts*total >= 9*settings.block_size*optimal_total,
            block_returns
        )
        fields = (
            name,
            sum(e.steps for e in learner.episodes),
            ending_counts([e.ending for e in learner.episodes])...,
            best,
            average_text(block_returns[best],settings.block_size),
            average_text(last(block_returns),settings.block_size),
            isnothing(reach) ? "-" : string(reach)
        )
        push!(training,join(fields,' '))
        order = sort(collect(1:n),by=state->(-totals[state],state))
        push!(visited,"$name "*join(("$(state_text(state)):$(totals[state])" for state in order[1:3]),' '))
        episode = last(learner.episodes)
        push!(
            last_episodes,
            "$name return $(episode.total) steps $(episode.steps) end $(episode.ending) $(cells_text(world,episode.cells))"
        )
        for (phase_first,phase_last) in phase_ranges(settings)
            episodes = learner.episodes[phase_first:phase_last]
            alpha,eps = schedule_value(settings.alpha_schedule,phase_first),schedule_value(
                settings.epsilon_schedule,
                phase_first
            )
            push!(
                phases,
                "$name $phase_first-$phase_last alpha $alpha epsilon $eps mean_return $(average_text(sum(e.total for e in episodes),length(episodes))) mean_steps $(average_text(sum(e.steps for e in episodes),length(episodes))) goals $(count(e->e.ending == "goal",episodes))"
            )
        end
    end
    append!(parts,[behaviour,q_errors,q_action_errors,rollout_lines,terminals])
    agreement = ["agreement","policy "*join(POLICY_NAMES,' ')]
    for (name,policy) in zip(POLICY_NAMES,policies)
        push!(agreement,"$name "*join((count_agreements(policy,other) for other in policies),' '))
    end
    append!(parts,[agreement,training,visited,last_episodes,phases])
    join_parts(parts)
end
function main()
    world = read_world(joinpath("input","world.txt"))
    settings = read_settings(joinpath("input","params.txt"))
    environment = Environment(
        world,
        settings.step_reward,
        settings.slip_total,
        settings.floor_slip,
        settings.ice_slip
    )
    values,changes = value_iteration(environment,settings.gamma,settings.theta)
    q = [
        bellman(environment,values,settings.gamma,state,action) for state in eachindex(values),
        action in 1:4
    ]
    optimal_policy = policy_of(q)
    optimal_actions = [findall(==(maximum(@view q[state,:])),@view q[state,:]) for state in eachindex(values)]
    _,in_place_sweeps = in_place_value_iteration(environment,settings.gamma,settings.theta)
    iteration_policy,iteration_values,rounds = policy_iteration(environment,settings.gamma,settings.theta)
    learners = [learn(method,environment,settings,values,optimal_policy) for method in METHODS]
    policies = vcat([optimal_policy,iteration_policy],[policy_of(learner.q) for learner in learners])
    evaluations = [evaluate_one(
        environment,
        policy,
        settings,
        values,
        optimal_policy,
        optimal_actions
    ) for policy in policies]
    table = vcat(["method,row,col,action,value,visits"],q_table_rows(world,"value_iteration",q,nothing))
    for learner in learners
        append!(table,q_table_rows(world,learner.method,learner.q,learner.visits))
    end
    outputs = (
        "values.txt"=>values_report(
            world,
            settings,
            environment,
            values,
            changes,
            q,
            optimal_policy,
            optimal_actions,
            in_place_sweeps,
            iteration_policy,
            iteration_values,
            rounds
        ),
        "policies.txt"=>policies_report(world,settings,environment,policies,learners),
        "q_tables.csv"=>table,"learning_curves.csv"=>learning_curves(learners,settings),
        "evaluation.txt"=>evaluation_report(world,settings,environment,values,q,policies,learners,evaluations)
    )
    mkpath("output")
    for (name,lines) in outputs
        write_lines(joinpath("output",name),lines)
    end
end
main()
