include("grid_map.jl")
include("low_level.jl")
include("cbs.jl")
include("prioritized.jl")
include("report.jl")

const CONFLICT_CLASSES = ("cardinal", "semi_cardinal", "non_cardinal")

function read_parameters(agent_count)
    settings = Dict{String,Any}(
        "orders" => Vector{Int}[collect(1:agent_count)],
        "runs" => NamedTuple[],
        "delays" => NTuple{3,Int}[]
    )
    for line in readlines("input/params.txt")
        fields = String.(split(line, ' '))
        kind, arguments = fields[1], fields[2:end]
        if kind in ("HORIZON", "HL_BUDGET", "LL_BUDGET")
            settings[lowercase(kind)] = parse(Int, arguments[1])
        elseif kind == "WINDOW"
            settings["window"], settings["step"] = parse.(Int, arguments)
        elseif kind == "ORDER"
            push!(settings["orders"], parse.(Int, arguments) .+ 1)
        elseif kind == "RUN"
            push!(
                settings["runs"],
                (name=join(arguments, "-"), solver=arguments[1], cost_function=arguments[2])
            )
        elseif kind == "ANIMATE"
            settings["animate"], settings["frames"] = arguments[1], parse(Int, arguments[2])
        else
            agent, start, duration = parse.(Int, arguments)
            push!(settings["delays"], (agent + 1, start, duration))
        end
    end
    return settings
end

function grid_statistics(grid)
    free_cells = findall(grid.free) .- 1
    degrees = [length(grid_neighbors(grid, cell)) for cell in free_cells]
    remaining = Set(free_cells)
    components = 0
    while !isempty(remaining)
        components += 1
        seed = minimum(remaining)
        delete!(remaining, seed)
        queue, index = [seed], 1
        while index <= length(queue)
            cell = queue[index]
            index += 1
            for other in grid_neighbors(grid, cell)
                if other in remaining
                    delete!(remaining, other)
                    push!(queue, other)
                end
            end
        end
    end
    return (
        isolated=count(==(0), degrees),
        dead_ends=count(==(1), degrees),
        corridors=count(==(2), degrees),
        junctions=count(>=(3), degrees),
        components=components
    )
end

function mdd_layers(grid, agent, distances, span, restrictions)
    layers = [Set{Int}() for _ in 0:span]
    push!(layers[1], agent.start)
    for time in 1:span
        for cell in layers[time], (destination, _) in destinations(grid, cell)
            if distances[destination + 1] >= 0 && time + distances[destination + 1] <= span && action_allowed(
                restrictions,
                cell,
                destination,
                time
            )
                push!(layers[time + 1], destination)
            end
        end
    end
    valid = [Set{Int}() for _ in 0:span]
    push!(valid[end], agent.goal)
    for time in span - 1:-1:0
        for source in layers[time + 1]
            if any(
                entry -> entry[1] in valid[time + 2] && action_allowed(
                    restrictions,
                    source,
                    entry[1],
                    time + 1
                ),
                destinations(grid, source)
            )
                push!(valid[time + 1], source)
            end
        end
    end
    return valid
end

function conflict_class(conflict, paths, restrictions, grid, agents, distances, cache)
    fixed = Bool[]
    for agent in (conflict.a, conflict.b)
        span = length(paths[agent]) - 1
        layers = get!(cache, agent) do
            mdd_layers(grid, agents[agent], distances[agent], span, restrictions[agent])
        end
        time = conflict.time
        forced = time > span ? true : conflict.kind == "vertex" ? length(layers[time + 1]) == 1 : length(layers[time]) == 1 && length(layers[time + 1]) == 1
        push!(fixed, forced)
    end
    return all(fixed) ? "cardinal" : any(fixed) ? "semi_cardinal" : "non_cardinal"
end

function independent_plan(grid, agents, distances, horizon)
    budget = SearchBudget()
    restrictions = Prohibitions()
    return [low_search(
        grid,
        agent,
        distances[index],
        agent.start,
        0,
        restrictions,
        horizon,
        budget
    ).path for (index, agent) in enumerate(agents)]
end

function conflict_groups(conflicts, agent_count)
    adjacent = [Set{Int}() for _ in 1:agent_count]
    for conflict in conflicts
        push!(adjacent[conflict.a], conflict.b)
        push!(adjacent[conflict.b], conflict.a)
    end
    seen, result = Set{Int}(), String[]
    for start in 1:agent_count
        (start in seen || isempty(adjacent[start])) && continue
        component, index = [start], 1
        push!(seen, start)
        while index <= length(component)
            current = component[index]
            index += 1
            for other in sort!(collect(adjacent[current]))
                if !(other in seen)
                    push!(seen, other)
                    push!(component, other)
                end
            end
        end
        push!(result, join(agent_name.(sort!(component))))
    end
    return result
end

function instance_overview(grid, agents, distances, independent)
    restrictions = [Prohibitions() for _ in agents]
    info = NamedTuple[]
    for (index, agent) in enumerate(agents)
        shortest = distances[index][agent.start + 1]
        layers = mdd_layers(grid, agent, distances[index], shortest, restrictions[index])
        push!(info, (shortest=shortest, mdd_states=sum(length, layers), mdd_width=maximum(length, layers)))
    end
    cache = Dict{Int,Any}()
    conflicts = [(
        ; conflict...,
        classification=conflict_class(conflict, independent, restrictions, grid, agents, distances, cache)
    ) for conflict in plan_conflicts(independent)]
    return (
        degrees=grid_statistics(grid),
        agents=info,
        soc_lower=sum(item.shortest for item in info),
        makespan_lower=maximum(item.shortest for item in info),
        conflicts=conflicts,
        groups=conflict_groups(conflicts, length(agents))
    )
end

mutable struct PathRun
    name::String
    solver::String
    cost_function::String
    status::String
    reason::String
    paths::Any
    high_level::Int
    generated::Int
    budget::SearchBudget
    specific::Vector{String}
    trace::Vector{String}
    ending::String
    metrics::Any
    validation::Any
    execution::Any
end

function new_run(definition, settings)
    return PathRun(
        definition.name,
        definition.solver,
        definition.cost_function,
        "FAIL",
        "",
        nothing,
        0,
        -1,
        SearchBudget(settings["ll_budget"]),
        String[],
        String[],
        "",
        nothing,
        nothing,
        nothing
    )
end

function solve_pp!(run, grid, agents, distances, settings)
    for (order_number, order) in enumerate(settings["orders"])
        run.high_level += 1
        before = run.budget.expansions
        result = try_priority_order(grid, agents, distances, settings["horizon"], order, run.budget)
        for attempt in result.attempts
            prefix = "order $order_number agent $(agent_name(attempt.agent))"
            detail = attempt.path === nothing ? "failed" : "cost $(length(attempt.path) - 1)"
            push!(run.trace, "$prefix $detail expansions $(attempt.expansions)")
        end
        if result.failure == "ll_budget"
            run.reason = "ll_budget"
            break
        end
        planned = length(result.attempts) - Int(!isempty(result.failure))
        summary = "order $order_number $(join(agent_name.(order))) planned $planned expansions $(run.budget.expansions - before)"
        if isempty(result.failure)
            push!(run.specific, summary * " ok")
            run.paths, run.status = result.paths, "OK"
            run.ending = "end OK order $order_number"
            return
        end
        push!(run.specific, summary * " failed " * agent_name(result.failed_agent))
    end
    isempty(run.reason) && (run.reason = "orders")
    run.ending = "end FAIL $(run.reason)"
end

function apply_constraint(base, addition)
    copied = copy(base)
    changed = copy_prohibitions(base[addition.agent])
    if addition.kind == "vertex"
        push!(changed.states, (addition.u, addition.time))
    else
        push!(changed.moves, (addition.u, addition.v, addition.time))
    end
    copied[addition.agent] = changed
    return copied
end

function choose_split(node, run, grid, agents, distances)
    run.solver == "CBS" && return node.conflicts[1], ""
    cache = Dict{Int,Any}()
    classes = [conflict_class(
        conflict,
        node.paths,
        node.constraints,
        grid,
        agents,
        distances,
        cache
    ) for conflict in node.conflicts]
    index = argmin([findfirst(==(category), CONFLICT_CLASSES) for category in classes])
    return node.conflicts[index], classes[index]
end

function solve_cbs!(run, grid, agents, distances, settings)
    empty_constraints = [Prohibitions() for _ in agents]
    paths = Vector{Int}[]
    for (index, agent) in enumerate(agents)
        result = low_search(
            grid,
            agent,
            distances[index],
            agent.start,
            0,
            empty_constraints[index],
            settings["horizon"],
            run.budget
        )
        if result.aborted
            run.reason, run.generated = "ll_budget", 0
            push!(run.specific, "search expanded 0 generated 0 pruned 0 open 0")
            run.solver == "ICBS" && push!(run.specific, "classes cardinal 0 semi_cardinal 0 non_cardinal 0")
            run.ending = "end FAIL ll_budget"
            return
        end
        push!(paths, result.path)
    end
    root = new_node(paths, empty_constraints, 0, 0, -1, run.cost_function)
    open = Any[root]
    generated, expanded, pruned = 1, 0, 0
    classes = Dict(category => 0 for category in CONFLICT_CLASSES)
    reason, answer = "exhausted", nothing
    while !isempty(open)
        node = binary_pop!(open, node_key)
        if isempty(node.conflicts)
            answer, reason = node, ""
            break
        end
        if expanded == settings["hl_budget"]
            reason = "hl_budget"
            break
        end
        expanded += 1
        conflict, category = choose_split(node, run, grid, agents, distances)
        !isempty(category) && (classes[category] += 1)
        created, aborted = String[], false
        for branch in split_constraints(conflict)
            agent = branch.agent
            constraints = apply_constraint(node.constraints, branch)
            result = low_search(
                grid,
                agents[agent],
                distances[agent],
                agents[agent].start,
                0,
                constraints[agent],
                settings["horizon"],
                run.budget
            )
            if result.aborted
                aborted = true
                break
            end
            if result.path === nothing
                pruned += 1
                push!(created, "-")
                continue
            end
            new_paths = copy(node.paths)
            new_paths[agent] = result.path
            child = new_node(
                new_paths,
                constraints,
                generated,
                node.depth + 1,
                node.number,
                run.cost_function
            )
            binary_push!(open, child, node_key)
            push!(created, string(generated))
            generated += 1
        end
        if aborted
            reason = "ll_budget"
            break
        end
        parent = node.parent == -1 ? "-" : string(node.parent)
        text = "expand $expanded node $(node.number) parent $parent depth $(node.depth) cost $(node.cost) conflicts $(length(node.conflicts)) split $(conflict_text(conflict, grid))"
        !isempty(category) && (text *= " class $category")
        push!(run.trace, text * " children $(created[1]) $(created[2])")
    end
    run.high_level, run.generated = expanded, generated
    push!(run.specific, "search expanded $expanded generated $generated pruned $pruned open $(length(open))")
    run.solver == "ICBS" && push!(
        run.specific,
        "classes cardinal $(classes["cardinal"]) semi_cardinal $(classes["semi_cardinal"]) non_cardinal $(classes["non_cardinal"])"
    )
    if answer === nothing
        run.reason, run.ending = reason, "end FAIL $reason"
        return
    end
    run.status, run.paths = "OK", answer.paths
    push!(run.specific, "solution node $(answer.number) depth $(answer.depth)")
    for constraint in ordered_constraints(answer, grid)
        beginning = "constraint $(agent_name(constraint.agent)) $(constraint.kind) $(cell_text(constraint.u, grid))"
        constraint.kind == "edge" && (beginning *= " " * cell_text(constraint.v, grid))
        push!(run.specific, beginning * " t $(constraint.time)")
    end
    run.ending = "end OK node $(answer.number) cost $(answer.cost)"
end

function solve_whca!(run, grid, agents, distances, settings)
    horizon, window, step = settings["horizon"], settings["window"], settings["step"]
    current, executed = [agent.start for agent in agents], [[agent.start] for agent in agents]
    time, rounds, reason = 0, 0, ""
    while !all(index -> current[index] == agents[index].goal, eachindex(agents))
        if time >= horizon
            reason = "timeout"
            break
        end
        rounds += 1
        restrictions = Prohibitions()
        order = vcat(
            [index for index in eachindex(agents) if current[index] != agents[index].goal],
            [index for index in eachindex(agents) if current[index] == agents[index].goal]
        )
        plans = [Int[] for _ in agents]
        for index in order
            result = low_search(
                grid,
                agents[index],
                distances[index],
                current[index],
                time,
                restrictions,
                time + window,
                run.budget; window=true
            )
            if result.aborted
                reason = "ll_budget"
                break
            end
            prefix = "round $rounds time $time agent $(agent_name(index))"
            if result.path === nothing
                push!(run.trace, "$prefix blocked expansions $(result.expansions)")
                reason = "blocked"
                break
            end
            path = vcat(result.path, fill(result.path[end], window + 1 - length(result.path)))
            plans[index] = path
            push!(run.trace, "$prefix moves $(action_string(path, grid)) expansions $(result.expansions)")
            reserve_path!(restrictions, path; start_time=time)
        end
        !isempty(reason) && break
        for index in eachindex(agents)
            append!(executed[index], plans[index][2:step + 1])
            current[index] = plans[index][step + 1]
        end
        time += step
    end
    run.high_level = rounds
    push!(run.specific, "window $window step $step rounds $rounds")
    if !isempty(reason)
        run.reason, run.ending = reason, "end FAIL $reason"
    else
        for (index, path) in enumerate(executed)
            while length(path) > 1 && path[end] == agents[index].goal && path[end - 1] == agents[index].goal
                pop!(path)
            end
        end
        run.status, run.paths, run.ending = "OK", executed, "end OK rounds $rounds"
    end
end

function validate_plan(paths, agents, grid)
    start_count = count(entry -> entry[1][1] != entry[2].start, zip(paths, agents))
    goal_count = count(entry -> entry[1][end] != entry[2].goal, zip(paths, agents))
    illegal = 0
    for path in paths, index in 2:length(path)
        !any(entry -> entry[1] == path[index], destinations(grid, path[index - 1])) && (illegal += 1)
    end
    collisions = plan_conflicts(paths)
    vertex = count(conflict -> conflict.kind == "vertex", collisions)
    edge = length(collisions) - vertex
    follows = 0
    for time in 1:maximum(length(path) - 1 for path in paths), a in eachindex(paths)
        past_a, next_a = path_position(paths[a], time - 1), path_position(paths[a], time)
        next_a == past_a && continue
        for b in eachindex(paths)
            a == b && continue
            next_a == path_position(
                paths[b],
                time - 1
            ) && path_position(paths[b], time) != past_a && (follows += 1)
        end
    end
    return (
        verdict=start_count + goal_count + illegal + vertex + edge == 0 ? "VALID" : "INVALID",
        start=start_count,
        goal=goal_count,
        moves=illegal,
        vertex=vertex,
        edge=edge,
        follows=follows,
        conflicts=collisions
    )
end

function path_statistics(path, goal, lower, grid)
    actions = action_string(path, grid)
    moves = [action for action in actions if action != '.']
    turns = count(index -> moves[index] != moves[index - 1], 2:length(moves))
    return (
        cost=length(path) - 1,
        extra=length(path) - 1 - lower,
        waits=count(==('.'), actions),
        turns=turns,
        arrive=findfirst(==(goal), path) - 1,
        leave=count(index -> path[index - 1] == goal && path[index] != goal, 2:length(path)),
        actions=actions
    )
end

function plan_statistics(paths, agents, overview, cost_function, grid)
    lengths = length.(paths) .- 1
    soc, makespan = sum(lengths), maximum(lengths)
    cost = cost_function == "SOC" ? soc : makespan
    lower = cost_function == "SOC" ? overview.soc_lower : overview.makespan_lower
    per_agent = [path_statistics(
        paths[index],
        agent.goal,
        overview.agents[index].shortest,
        grid
    ) for (index, agent) in enumerate(agents)]
    arrivals = [count(<=(time), lengths) for time in 0:makespan]
    traffic, cell_waits = Dict{Int,Int}(), Dict{Int,Int}()
    for path in paths
        for cell in Set(path)
            traffic[cell] = get(traffic, cell, 0) + 1
        end
        for index in 2:length(path)
            path[index - 1] == path[index] && (cell_waits[path[index]] = get(cell_waits, path[index], 0) + 1)
        end
    end
    hotspots = sort!(collect(keys(traffic)); by=cell -> (
        -traffic[cell],
        cell ÷ grid.width,
        cell % grid.width
    ))
    resize!(hotspots, min(5, length(hotspots)))
    return (
        ; soc,
        makespan,
        cost,
        ratio=reduced_fraction(cost, lower),
        agents=per_agent,
        sum_extra=sum(item.extra for item in per_agent),
        max_extra=maximum(item.extra for item in per_agent),
        waits=sum(item.waits for item in per_agent),
        turns=sum(item.turns for item in per_agent),
        arrivals,
        traffic,
        cell_waits,
        hotspots
    )
end

function delayed_execution(paths, settings)
    steps = Vector{Tuple{Int,Int}}[]
    by_cell = Dict{Int,Vector{NTuple{3,Int}}}()
    for (agent, path) in enumerate(paths)
        entries = [(0, path[1])]
        for time in 1:length(path) - 1
            path[time + 1] != path[time] && push!(entries, (time, path[time + 1]))
        end
        push!(steps, entries)
        for (index, (time, cell)) in enumerate(entries)
            push!(get!(by_cell, cell, NTuple{3,Int}[]), (agent, index - 1, time))
        end
    end
    prerequisites = [[Tuple{Int,Int}[] for _ in entries] for entries in steps]
    for (agent, entries) in enumerate(steps), index in 2:length(entries)
        scheduled, cell = entries[index]
        for (other, step, time) in by_cell[cell]
            other != agent && time < scheduled && push!(prerequisites[agent][index], (other, step))
        end
    end
    progress, finish = zeros(Int, length(paths)), zeros(Int, length(paths))
    holds, time = 0, 0
    while any(index -> progress[index] < length(steps[index]) - 1, eachindex(paths))
        advance, stopped = Int[], 0
        for agent in eachindex(paths)
            progress[agent] == length(steps[agent]) - 1 && continue
            if any(delay -> delay[1] == agent && delay[2] <= time < delay[2] + delay[3], settings["delays"])
                stopped += 1
            elseif all(
                requirement -> progress[requirement[1]] > requirement[2],
                prerequisites[agent][progress[agent] + 2]
            )
                push!(advance, agent)
            else
                holds += 1
            end
        end
        isempty(advance) && stopped == 0 && return (
            deadlock=time,
            blocked=holds,
            finish=finish,
            soc=0,
            makespan=0
        )
        for agent in advance
            progress[agent] += 1
            progress[agent] == length(steps[agent]) - 1 && (finish[agent] = time + 1)
        end
        time += 1
    end
    return (deadlock=-1, blocked=holds, finish=finish, soc=sum(finish), makespan=maximum(finish))
end

function instance_lines(grid, agents, overview)
    degrees = overview.degrees
    lines = [
        "instance width $(grid.width) height $(grid.height) free $(count(grid.free)) agents $(length(agents))",
        "map isolated $(degrees.isolated) dead_ends $(degrees.dead_ends) corridors $(degrees.corridors) junctions $(degrees.junctions) components $(degrees.components)"
    ]
    for (index, agent) in enumerate(agents)
        info = overview.agents[index]
        push!(
            lines,
            "agent $(agent.name) start $(cell_text(agent.start, grid)) goal $(cell_text(agent.goal, grid)) distance $(info.shortest) mdd $(info.mdd_states) width $(info.mdd_width)"
        )
    end
    push!(lines, "lower_bound soc $(overview.soc_lower) makespan $(overview.makespan_lower)")
    conflicts = overview.conflicts
    classes = join(
        ("$category $(count(conflict -> conflict.classification == category, conflicts))" for category in CONFLICT_CLASSES),
        " "
    )
    vertex = count(conflict -> conflict.kind == "vertex", conflicts)
    push!(
        lines,
        "independent conflicts $(length(conflicts)) vertex $vertex edge $(length(conflicts) - vertex) $classes"
    )
    push!(lines, "groups " * (isempty(overview.groups) ? "-" : join(overview.groups, " ")))
    return lines
end

function successful_run_lines(run, agents)
    metrics, execution = run.metrics, run.execution
    lines = ["run $(run.name) solver $(run.solver) cost_function $(run.cost_function) result OK cost $(metrics.cost) soc $(metrics.soc) makespan $(metrics.makespan) ratio $(metrics.ratio)"]
    append!(lines, run.specific)
    for (agent, info) in zip(agents, metrics.agents)
        push!(
            lines,
            "agent $(agent.name) cost $(info.cost) extra $(info.extra) waits $(info.waits) turns $(info.turns) arrive $(info.arrive) leave $(info.leave) moves $(info.actions)"
        )
    end
    push!(lines, "arrivals " * join(metrics.arrivals, " "))
    push!(
        lines,
        "hotspots " * join(
            ("$(cell_text(cell, run.metrics.grid)):$(metrics.traffic[cell])" for cell in metrics.hotspots),
            " "
        )
    )
    if execution.deadlock >= 0
        push!(lines, "execution deadlock time $(execution.deadlock)")
    else
        push!(
            lines,
            "execution soc $(execution.soc) makespan $(execution.makespan) blocked $(execution.blocked) finish $(join(execution.finish, " "))"
        )
    end
    return lines
end

function solution_lines(grid, agents, overview, runs)
    lines = instance_lines(grid, agents, overview)
    for run in runs
        push!(lines, "")
        if run.status == "OK"
            append!(lines, successful_run_lines(run, agents))
        else
            push!(
                lines,
                "run $(run.name) solver $(run.solver) cost_function $(run.cost_function) result FAIL reason $(run.reason)"
            )
            append!(lines, run.specific)
        end
    end
    push!(lines, "")
    succeeded = [run for run in runs if run.status == "OK"]
    push!(lines, "summary ok $(length(succeeded)) failed $(length(runs) - length(succeeded))")
    if !isempty(succeeded)
        soc, span = minimum(run.metrics.soc for run in succeeded), minimum(run.metrics.makespan for run in succeeded)
        push!(lines, "best_soc $soc " * join((run.name for run in succeeded if run.metrics.soc == soc), " "))
        push!(
            lines,
            "best_makespan $span " * join(
                (run.name for run in succeeded if run.metrics.makespan == span),
                " "
            )
        )
        ranked = sort(succeeded; by=run -> (run.metrics.soc, run.metrics.makespan), alg=MergeSort)
        push!(lines, "ranking " * join((run.name for run in ranked), " "))
    end
    return lines
end

function stats_lines(runs)
    lines = ["run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"]
    for run in runs
        fields = Any[
            run.name,
            run.solver,
            run.cost_function,
            run.status,
            isempty(run.reason) ? "-" : run.reason
        ]
        if run.status == "OK"
            metrics, execution = run.metrics, run.execution
            append!(
                fields,
                [
                    metrics.cost,
                    metrics.soc,
                    metrics.makespan,
                    metrics.sum_extra,
                    metrics.max_extra,
                    metrics.waits,
                    metrics.turns
                ]
            )
            append!(fields, execution.deadlock == -1 ? Any[execution.soc, execution.makespan] : Any["-", "-"])
        else
            append!(fields, fill("-", 9))
        end
        push!(
            fields,
            run.high_level,
            run.generated == -1 ? "-" : run.generated,
            run.budget.searches,
            run.budget.expansions
        )
        push!(lines, csv_line(fields))
    end
    return lines
end

function validation_lines(runs, independent, agents, grid, overview)
    baseline = (; validate_plan(independent, agents, grid)..., conflicts=overview.conflicts)
    plans = Any[("INDEPENDENT", baseline)]
    append!(plans, [(run.name, run.validation) for run in runs])
    lines = String[]
    for (name, validation) in plans
        if validation === nothing
            push!(lines, "plan $name verdict NONE")
            continue
        end
        push!(
            lines,
            "plan $name verdict $(validation.verdict) start $(validation.start) goal $(validation.goal) moves $(validation.moves) vertex $(validation.vertex) edge $(validation.edge) follows $(validation.follows)"
        )
        for conflict in validation.conflicts
            text = "  " * conflict_text(conflict, grid)
            name == "INDEPENDENT" && (text *= " " * conflict.classification)
            push!(lines, text)
        end
    end
    return lines
end

function trace_lines(runs)
    lines = String[]
    for (index, run) in enumerate(runs)
        index > 1 && push!(lines, "")
        push!(lines, "run $(run.name)")
        append!(lines, run.trace)
        push!(lines, run.ending)
    end
    return lines
end

function animation_lines(runs, grid, agents, settings)
    selected = first(run for run in runs if run.name == settings["animate"])
    selected.status != "OK" && return ["run $(selected.name) FAIL"]
    frames, paths = settings["frames"], selected.paths
    lines = ["run $(selected.name) frames $frames"]
    for time in 0:frames - 1
        done = count(path -> time >= length(path) - 1, paths)
        moving = count(
            path -> time < length(path) - 1 && time >= 1 && path_position(path, time) != path_position(
                path,
                time - 1
            ),
            paths
        )
        waiting = length(paths) - done - moving
        push!(lines, "", "frame $time done $done moving $moving waiting $waiting")
        placements = Dict(agent.goal => lowercase(agent.name) for agent in agents)
        for (agent, path) in zip(agents, paths)
            placements[path_position(path, time)] = agent.name
        end
        append!(lines, grid_picture(grid, placements))
    end
    for (name, counts) in (("traffic", selected.metrics.traffic), ("waits", selected.metrics.cell_waits))
        push!(lines, "", name)
        placements = Dict(cell => value <= 9 ? string(value)[1] : '+' for (
            cell,
            value
        ) in counts if value > 0)
        append!(lines, grid_picture(grid, placements))
    end
    return lines
end

function main()
    grid = read_grid()
    agents = read_agents(grid)
    settings = read_parameters(length(agents))
    distances = [distance_table(grid, agent.goal) for agent in agents]
    independent = independent_plan(grid, agents, distances, settings["horizon"])
    overview = instance_overview(grid, agents, distances, independent)
    runs = PathRun[]
    for definition in settings["runs"]
        run = new_run(definition, settings)
        if run.solver == "PP"
            solve_pp!(run, grid, agents, distances, settings)
        elseif run.solver in ("CBS", "ICBS")
            solve_cbs!(run, grid, agents, distances, settings)
        else
            solve_whca!(run, grid, agents, distances, settings)
        end
        if run.status == "OK"
            run.metrics = (
                ; plan_statistics(run.paths, agents, overview, run.cost_function, grid)...,
                grid=grid
            )
            run.validation = validate_plan(run.paths, agents, grid)
            run.execution = delayed_execution(run.paths, settings)
        end
        push!(runs, run)
    end
    save_file("solutions.txt", solution_lines(grid, agents, overview, runs))
    save_file("stats.csv", stats_lines(runs))
    save_file("validation.txt", validation_lines(runs, independent, agents, grid, overview))
    save_file("trace.txt", trace_lines(runs))
    save_file("frames.txt", animation_lines(runs, grid, agents, settings))
end

main()
