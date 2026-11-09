mutable struct SearchBudget
    limit::Int
    searches::Int
    expansions::Int
end
SearchBudget(limit=typemax(Int)) = SearchBudget(limit, 0, 0)

struct Prohibitions
    states::Set{Tuple{Int,Int}}
    moves::Set{NTuple{3,Int}}
    permanent::Dict{Int,Int}
end
Prohibitions() = Prohibitions(Set{Tuple{Int,Int}}(), Set{NTuple{3,Int}}(), Dict{Int,Int}())
copy_prohibitions(base) = Prohibitions(copy(base.states), copy(base.moves), copy(base.permanent))
state_allowed(restrictions, cell, time) = !((cell, time) in restrictions.states) && time < get(
    restrictions.permanent,
    cell,
    typemax(Int)
)
action_allowed(
    restrictions,
    source,
    destination,
    time
) = state_allowed(
    restrictions,
    destination,
    time
) && (source == destination || !((source, destination, time) in restrictions.moves))
arrival_allowed(
    restrictions,
    goal
) = maximum((time + 1 for (cell, time) in restrictions.states if cell == goal); init=0)

function reserve_path!(restrictions, path; start_time=0, permanent=false)
    for (index, cell) in enumerate(path)
        time = start_time + index - 1
        push!(restrictions.states, (cell, time))
        index > 1 && path[index - 1] != cell && push!(restrictions.moves, (cell, path[index - 1], time))
    end
    if permanent
        restrictions.permanent[path[end]] = min(
            get(restrictions.permanent, path[end], typemax(Int)),
            start_time + length(path) - 1
        )
    end
end

function binary_push!(heap, item, key)
    push!(heap, item)
    index = length(heap)
    while index > 1
        parent = index ÷ 2
        key(heap[parent]) <= key(heap[index]) && break
        heap[parent], heap[index] = heap[index], heap[parent]
        index = parent
    end
end

function binary_pop!(heap, key)
    result, final = heap[1], pop!(heap)
    if !isempty(heap)
        heap[1] = final
        index = 1
        while 2 * index <= length(heap)
            child = 2 * index
            child < length(heap) && key(heap[child + 1]) < key(heap[child]) && (child += 1)
            key(heap[index]) <= key(heap[child]) && break
            heap[index], heap[child] = heap[child], heap[index]
            index = child
        end
    end
    return result
end

function low_search(grid, agent, distances, start, t0, restrictions, tmax, budget; window=false)
    budget.searches += 1
    beginning = budget.expansions
    arrival = arrival_allowed(restrictions, agent.goal)
    area = length(grid.free)
    parents = fill(-1, area * (tmax - t0 + 1))
    root = start + 1
    parents[root] = 0
    heap = [(distances[start + 1], 0, 0, root)]
    insertion = 0
    while !isempty(heap)
        _, negative_g, _, state = binary_pop!(heap, identity)
        budget.expansions += 1
        budget.expansions > budget.limit && return (
            path=nothing,
            expansions=budget.expansions - beginning,
            aborted=true
        )
        cell, time = (state - 1) % area, t0 - negative_g
        if (cell == agent.goal && time >= arrival) || (window && time == tmax)
            reversed_path = Int[]
            current = state
            while current != 0
                push!(reversed_path, (current - 1) % area)
                current = parents[current]
            end
            return (path=reverse(reversed_path), expansions=budget.expansions - beginning, aborted=false)
        end
        time == tmax && continue
        for (destination, _) in destinations(grid, cell)
            distances[destination + 1] < 0 && continue
            next_time = time + 1
            next_state = destination + 1 + (next_time - t0) * area
            (parents[next_state] != -1 || !action_allowed(
                restrictions,
                cell,
                destination,
                next_time
            )) && continue
            insertion += 1
            parents[next_state] = state
            g = next_time - t0
            binary_push!(heap, (g + distances[destination + 1], -g, insertion, next_state), identity)
        end
    end
    return (path=nothing, expansions=budget.expansions - beginning, aborted=false)
end
