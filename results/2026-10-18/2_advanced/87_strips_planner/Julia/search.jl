applicable(action,state) = issubset(action.pre,state) && isdisjoint(action.neg,state)
apply_action(action,state) = union(setdiff(state,action.delete),action.add)
search_result(status,expanded=0,generated=0,plan=Int[]) = (status=status,expanded=expanded,generated=generated,plan=plan)
mutable struct SearchNode
    state::Set{Int}
    g::Int
    depth::Int
    parent::Int
    action::Int
end
function heap_push!(heap,entry)
    push!(heap,entry)
    i = length(heap)
    while i > 1
        parent = i ÷ 2
        heap[parent][1] <= entry[1] && break
        heap[i] = heap[parent]
        i = parent
    end
    heap[i] = entry
end
function heap_pop!(heap)
    first = heap[1]
    last = pop!(heap)
    if !isempty(heap)
        i = 1
        while 2*i <= length(heap)
            child = 2*i
            child < length(heap) && heap[child+1][1] < heap[child][1] && (child += 1)
            last[1] <= heap[child][1] && break
            heap[i] = heap[child]
            i = child
        end
        heap[i] = last
    end
    first
end
function search_priority(algorithm,g,depth,h,weight)
    algorithm == "bfs" && return depth
    algorithm == "ucs" && return g
    algorithm == "gbfs" && return h
    g+h*(algorithm == "wastar" ? weight : 1)
end
function best_first(problem,start,algorithm,heuristic,budget,weight,engine)
    initial_h = heuristic_value(engine,heuristic,start)
    initial_h == INFINITY && return search_result("dead end")
    nodes = [SearchNode(start,0,0,0,-1)]
    heap = [((search_priority(algorithm,0,0,initial_h,weight),initial_h,0),1)]
    best = Dict(state_key(start) => 0)
    serial,expanded,generated = 1,0,0
    reopen = algorithm in ("ucs","astar","wastar")
    while !isempty(heap)
        _,index = heap_pop!(heap)
        node = nodes[index]
        reopen && node.g > best[state_key(node.state)] && continue
        if issubset(problem.goal,node.state)
            plan = Int[]
            while nodes[index].parent != 0
                push!(plan,nodes[index].action)
                index = nodes[index].parent
            end
            return search_result("solved",expanded,generated,reverse(plan))
        end
        expanded == budget && return search_result("budget",expanded,generated)
        expanded += 1
        for action in problem.actions
            applicable(action,node.state) || continue
            state = apply_action(action,node.state)
            generated += 1
            cost,key = node.g+action.cost,state_key(state)
            haskey(best,key) && (!reopen || best[key] <= cost) && continue
            best[key] = cost
            h = heuristic_value(engine,heuristic,state)
            h == INFINITY && continue
            child = SearchNode(state,cost,node.depth+1,index,action.number)
            push!(nodes,child)
            heap_push!(heap,((search_priority(algorithm,cost,child.depth,h,weight),h,serial),length(nodes)))
            serial += 1
        end
    end
    search_result("exhausted",expanded,generated)
end
function hill_climbing(problem,start,heuristic,budget,engine)
    current,plan = start,Int[]
    current_h = heuristic_value(engine,heuristic,current)
    expanded,generated = 0,0
    current_h == INFINITY && return search_result("dead end")
    while !issubset(problem.goal,current)
        queue = [(state=current,path=Int[])]
        visited = Set([state_key(current)])
        head,improved = 1,false
        while head <= length(queue) && !improved
            entry = queue[head]
            head += 1
            expanded == budget && return search_result("budget",expanded,generated)
            expanded += 1
            for number in helpful(engine,entry.state)
                state = apply_action(problem.actions[number+1],entry.state)
                generated += 1
                key = state_key(state)
                key in visited && continue
                push!(visited,key)
                h = heuristic_value(engine,heuristic,state)
                h == INFINITY && continue
                path = [entry.path;number]
                if h < current_h
                    append!(plan,path)
                    current,current_h,improved = state,h,true
                    break
                end
                push!(queue,(state=state,path=path))
            end
        end
        improved || return search_result("stuck",expanded,generated)
    end
    search_result("solved",expanded,generated,plan)
end
function run_search(problem,start,algorithm,heuristic,budget,weight,engine)
    algorithm == "ehc" ? hill_climbing(problem,start,heuristic,budget,engine) :
        best_first(problem,start,algorithm,heuristic,budget,weight,engine)
end
