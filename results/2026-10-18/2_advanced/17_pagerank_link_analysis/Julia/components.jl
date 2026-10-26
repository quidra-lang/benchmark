function strong_components(adjacency)
    n = length(adjacency)
    order, low, on_stack = zeros(Int, n), zeros(Int, n), falses(n)
    stack, groups = Int[], Vector{Int}[]
    counter = 0
    for root in 1:n
        order[root] != 0 && continue
        counter += 1
        order[root] = low[root] = counter
        push!(stack, root)
        on_stack[root] = true
        work = [(root, 1)]
        while !isempty(work)
            node, position = work[end]
            if position <= length(adjacency[node])
                work[end] = (node, position + 1)
                child = adjacency[node][position]
                if order[child] == 0
                    counter += 1
                    order[child] = low[child] = counter
                    push!(stack, child)
                    on_stack[child] = true
                    push!(work, (child, 1))
                elseif on_stack[child]
                    low[node] = min(low[node], order[child])
                end
                continue
            end
            pop!(work)
            !isempty(work) && (low[work[end][1]] = min(low[work[end][1]], low[node]))
            if low[node] == order[node]
                group = Int[]
                while true
                    member = pop!(stack)
                    on_stack[member] = false
                    push!(group, member)
                    member == node && break
                end
                push!(groups, group)
            end
        end
    end
    groups
end

function reachable(adjacency, starts)
    seen, stack = falses(length(adjacency)), Int[]
    for start in starts
        if !seen[start]
            seen[start] = true
            push!(stack, start)
        end
    end
    while !isempty(stack)
        for child in adjacency[pop!(stack)]
            if !seen[child]
                seen[child] = true
                push!(stack, child)
            end
        end
    end
    seen
end

function bfs_distances(adjacency, starts)
    distances, queue, head = fill(-1, length(adjacency)), Int[], 1
    for start in starts
        if distances[start] == -1
            distances[start] = 0
            push!(queue, start)
        end
    end
    while head <= length(queue)
        node = queue[head]
        head += 1
        for child in adjacency[node]
            if distances[child] == -1
                distances[child] = distances[node] + 1
                push!(queue, child)
            end
        end
    end
    distances
end

function weak_components(adjacency)
    labels, number = zeros(Int, length(adjacency)), 0
    for root in eachindex(adjacency)
        labels[root] != 0 && continue
        number += 1
        labels[root] = number
        stack = [root]
        while !isempty(stack)
            for child in adjacency[pop!(stack)]
                if labels[child] == 0
                    labels[child] = number
                    push!(stack, child)
                end
            end
        end
    end
    labels
end
