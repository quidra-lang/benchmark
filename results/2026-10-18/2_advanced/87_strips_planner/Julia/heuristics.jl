const HEURISTIC_NAMES = ["goalcount","hmax","hadd","ff","lmcount"]
const INFINITY = typemax(Int) ÷ 8
state_key(state) = Tuple(sort(collect(state)))
mutable struct HeuristicEngine
    problem::Any
    achievers::Vector{Vector{Int}}
    cache::Dict{Tuple,Any}
end
function new_evaluator(problem)
    achievers = [Int[] for _ in problem.facts]
    for action in problem.actions, fact in action.add
        push!(achievers[fact+1],action.number)
    end
    HeuristicEngine(problem,achievers,Dict{Tuple,Any}())
end
function relaxed_costs(engine,state,maximum_cost)
    get!(engine.cache,(maximum_cost ? "cmax" : "cadd",state_key(state))) do
        costs = [p-1 in state ? 0 : INFINITY for p in eachindex(engine.problem.facts)]
        while true
            changed = false
            for action in engine.problem.actions
                values = [costs[p+1] for p in action.pre]
                INFINITY in values && continue
                aggregate = maximum_cost ? maximum(values;init=0) : sum(values;init=0)
                value = action.cost+aggregate
                for p in action.add
                    if value < costs[p+1]
                        costs[p+1] = value
                        changed = true
                    end
                end
            end
            changed || break
        end
        costs
    end
end
function relaxed_plan(engine,state)
    get!(engine.cache,("plan",state_key(state))) do
        costs = relaxed_costs(engine,state,false)
        any(costs[g+1] == INFINITY for g in engine.problem.goal) && return nothing
        chosen = Set{Int}()
        pending = sort(collect(setdiff(engine.problem.goal,state)))
        while !isempty(pending)
            fact = pop!(pending)
            winner,lowest = -1,INFINITY
            for number in engine.achievers[fact+1]
                action = engine.problem.actions[number+1]
                values = [costs[p+1] for p in action.pre]
                INFINITY in values && continue
                value = action.cost+sum(values;init=0)
                if value < lowest
                    winner,lowest = number,value
                end
            end
            if !(winner in chosen)
                push!(chosen,winner)
                append!(pending,sort(collect(setdiff(engine.problem.actions[winner+1].pre,state))))
            end
        end
        sort(collect(chosen))
    end
end
function helpful(engine,state)
    plan = relaxed_plan(engine,state)
    plan === nothing ? Int[] : [n for n in plan if applicable(engine.problem.actions[n+1],state)]
end
function planning_levels(engine,state)
    get!(engine.cache,("levels",state_key(state))) do
        facts = [p-1 in state ? 0 : INFINITY for p in eachindex(engine.problem.facts)]
        actions = fill(INFINITY,length(engine.problem.actions))
        level = 0
        while true
            changed = false
            for action in engine.problem.actions
                actions[action.number+1] != INFINITY && continue
                any(facts[p+1] > level for p in action.pre) && continue
                actions[action.number+1] = level
                for p in action.add
                    if facts[p+1] == INFINITY
                        facts[p+1] = level+1
                        changed = true
                    end
                end
            end
            !changed && return facts,actions
            level += 1
        end
    end
end
function verified_landmark(engine,state,excluded)
    reachable = copy(state)
    while true
        changed = false
        for action in engine.problem.actions
            excluded in action.add && continue
            if issubset(action.pre,reachable)
                added = setdiff(action.add,reachable)
                if !isempty(added)
                    union!(reachable,added)
                    changed = true
                end
            end
        end
        changed || break
    end
    !issubset(engine.problem.goal,reachable)
end
function landmarks(engine,state)
    get!(engine.cache,("landmarks",state_key(state))) do
        fact_levels,action_levels = planning_levels(engine,state)
        any(fact_levels[g+1] == INFINITY for g in engine.problem.goal) && return nothing
        result = setdiff(engine.problem.goal,state)
        pending = sort(collect(result))
        verified = Dict{Int,Bool}()
        head = 1
        while head <= length(pending)
            fact = pending[head]
            head += 1
            earliest = [engine.problem.actions[n+1].pre for n in engine.achievers[fact+1]
                if action_levels[n+1] == fact_levels[fact+1]-1]
            candidates = copy(earliest[1])
            for pre in earliest[2:end]
                intersect!(candidates,pre)
            end
            for p in sort(collect(setdiff(candidates,union(state,result))))
                valid = get!(verified,p) do
                    verified_landmark(engine,state,p)
                end
                if valid
                    push!(result,p)
                    push!(pending,p)
                end
            end
        end
        result
    end
end
function heuristic_value(engine,name,state)
    name == "none" && return 0
    get!(engine.cache,(name,state_key(state))) do
        if name == "goalcount"
            return length(setdiff(engine.problem.goal,state))
        elseif name in ("hmax","hadd")
            costs = relaxed_costs(engine,state,name == "hmax")
            values = [costs[p+1] for p in engine.problem.goal]
            INFINITY in values && return INFINITY
            return name == "hmax" ? maximum(values;init=0) : sum(values;init=0)
        elseif name == "ff"
            plan = relaxed_plan(engine,state)
            return plan === nothing ? INFINITY : sum((engine.problem.actions[n+1].cost for n in plan);init=0)
        end
        selected = landmarks(engine,state)
        selected === nothing ? INFINITY : length(selected)
    end
end
heuristic_values(engine,state) = [heuristic_value(engine,name,state) for name in HEURISTIC_NAMES]
