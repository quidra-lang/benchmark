struct GraphElement
    number::Union{Nothing,Int}
    pre::Set{Int}
    add::Set{Int}
    delete::Set{Int}
end
mutex_pair(a,b) = a < b ? (a,b) : (b,a)
function graph_conflict(a,b,mutexes)
    !isdisjoint(a.delete,union(b.pre,b.add)) || !isdisjoint(b.delete,union(a.pre,a.add)) ||
        any(mutex_pair(p,q) in mutexes for p in a.pre for q in b.pre)
end
function solve_graphplan(actions,initial,goal,limit)
    facts,mutexes = [initial],[Set{Tuple{Int,Int}}()]
    levels = Vector{GraphElement}[]
    exclusive_levels = Set{Tuple{Int,Int}}[]
    achiever_levels = Dict{Int,Vector{Int}}[]
    memo = Set{Tuple}()
    lines = String[]
    searched,memo_hits,tried = 0,0,0
    function extract(level,goals)
        level == 0 && return Vector{Int}[]
        key = (level,Tuple(goals))
        if key in memo
            memo_hits += 1
            return nothing
        end
        searched += 1
        layers = assign(level,goals,1,Int[])
        layers === nothing && push!(memo,key)
        layers
    end
    function assign(level,goals,position,chosen)
        elements = levels[level]
        while position <= length(goals) && any(goals[position] in elements[i].add for i in chosen)
            position += 1
        end
        if position > length(goals)
            previous = sort(collect(Set(p for i in chosen for p in elements[i].pre)))
            layers = extract(level-1,previous)
            layers === nothing && return nothing
            layer = sort([elements[i].number for i in chosen if elements[i].number !== nothing])
            push!(layers,Int.(layer))
            return layers
        end
        for i in achiever_levels[level][goals[position]]
            any(mutex_pair(i,j) in exclusive_levels[level] for j in chosen) && continue
            tried += 1
            layers = assign(level,goals,position+1,[chosen;i])
            layers === nothing || return layers
        end
        nothing
    end
    function finish(status,layers=Vector{Int}[])
        (status=status,plan=[n for layer in layers for n in layer],layers=layers,lines=lines,
            expanded=searched,generated=tried,memo_hits=memo_hits)
    end
    for level in 0:limit
        current,current_mutexes = facts[level+1],mutexes[level+1]
        push!(lines,"fact level $level: facts=$(length(current)) mutexes=$(length(current_mutexes))")
        ordered_goal = sort(collect(goal))
        possible = issubset(goal,current) && !any(mutex_pair(p,q) in current_mutexes for p in goal for q in goal if p < q)
        if possible
            before_search,before_hits = searched,memo_hits
            layers = extract(level,ordered_goal)
            outcome = layers === nothing ? "fail" : "success"
            push!(lines,"extract level $level: $outcome searched=$(searched-before_search) memo_hits=$(memo_hits-before_hits)")
            layers === nothing || return finish("solved",layers)
        elseif level >= 1 && length(current) == length(facts[level]) && length(current_mutexes) == length(mutexes[level])
            return finish("unreachable")
        end
        level == limit && return finish("level limit")
        elements = [GraphElement(a.number,a.pre,a.add,a.delete) for a in actions if issubset(a.pre,current) &&
            !any(mutex_pair(p,q) in current_mutexes for p in a.pre for q in a.pre if p < q)]
        action_count = length(elements)
        append!(elements,[GraphElement(nothing,Set([p]),Set([p]),Set{Int}()) for p in sort(collect(current))])
        exclusive = Set{Tuple{Int,Int}}()
        for i in eachindex(elements), j in (i+1):length(elements)
            graph_conflict(elements[i],elements[j],current_mutexes) && push!(exclusive,(i,j))
        end
        push!(lines,"action level $level: actions=$action_count noops=$(length(current)) mutexes=$(length(exclusive))")
        achievers = Dict{Int,Vector{Int}}()
        for (i,element) in enumerate(elements), p in element.add
            push!(get!(achievers,p,Int[]),i)
        end
        for producers in values(achievers)
            sort!(producers;by=i -> elements[i].number === nothing ? -1 : elements[i].number)
        end
        following = Set(keys(achievers))
        following_mutexes = Set{Tuple{Int,Int}}()
        ordered = sort(collect(following))
        for i in eachindex(ordered), j in (i+1):length(ordered)
            p,q = ordered[i],ordered[j]
            all(x != y && mutex_pair(x,y) in exclusive for x in achievers[p] for y in achievers[q]) &&
                push!(following_mutexes,(p,q))
        end
        push!(levels,elements)
        push!(exclusive_levels,exclusive)
        push!(achiever_levels,achievers)
        push!(facts,following)
        push!(mutexes,following_mutexes)
    end
    finish("level limit")
end
