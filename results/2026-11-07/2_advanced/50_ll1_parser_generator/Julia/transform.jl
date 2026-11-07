clone_grammar(g) = Grammar(copy(g.order),Dict(lhs=>deepcopy(g.rules[lhs]) for lhs in g.order),g.start)
function fresh_name(symbol,rules)
    proposed = symbol[1:end-1]*"'>"
    while haskey(rules,proposed)
        proposed = proposed[1:end-1]*"'>"
    end
    proposed
end
function leading_reaches(rules,source,target)
    queue,seen = [source],Set([source])
    cursor = 1
    while cursor<=length(queue)
        current = queue[cursor]
        cursor += 1
        for row in rules[current]
            (isempty(row) || !is_nonterminal(row[1])) && continue
            next = row[1]
            next==target && return true
            if !(next in seen)
                push!(seen,next)
                push!(queue,next)
            end
        end
    end
    false
end
function eliminate_left_recursion(grammar)
    g = clone_grammar(grammar)
    initial,log = copy(g.order),String[]
    for (i,lhs) in enumerate(initial)
        for earlier in initial[1:i-1]
            current = g.rules[lhs]
            if any(row->!isempty(row) && row[1]==earlier,current) && leading_reaches(g.rules,earlier,lhs)
                replacements = Vector{String}[]
                for row in current
                    if !isempty(row) && row[1]==earlier
                        append!(replacements,[vcat(source,row[2:end]) for source in g.rules[earlier]])
                    else
                        push!(replacements,row)
                    end
                end
                g.rules[lhs] = unique(replacements)
                push!(log,"substitute $earlier into $lhs")
            end
        end
        source = Vector{String}[]
        for row in g.rules[lhs]
            if row==[lhs]
                push!(log,"remove cycle $lhs -> $lhs")
            else
                push!(source,row)
            end
        end
        recursive = [row[2:end] for row in source if !isempty(row) && row[1]==lhs]
        if isempty(recursive)
            g.rules[lhs] = source
        else
            ordinary = [row for row in source if isempty(row) || row[1]!=lhs]
            created = fresh_name(lhs,g.rules)
            g.rules[lhs] = [vcat(row,[created]) for row in ordinary]
            g.rules[created] = vcat([vcat(row,[created]) for row in recursive],[String[]])
            insert!(g.order,findfirst(==(lhs),g.order)+1,created)
            push!(log,"eliminate left recursion in $lhs with $created")
        end
    end
    g,log
end
function left_factor(grammar)
    g,log = clone_grammar(grammar),String[]
    position = 1
    while position<=length(g.order)
        lhs = g.order[position]
        current,insertions = g.rules[lhs],String[]
        index = 1
        while index<=length(current)
            row = current[index]
            if isempty(row)
                index += 1
                continue
            end
            group = findall(other->!isempty(other) && other[1]==row[1],current)
            if length(group)==1
                index += 1
                continue
            end
            limit = minimum(length(current[i]) for i in group)
            prefix_length = 0
            while prefix_length<limit && all(i->current[i][prefix_length+1]==row[prefix_length+1],group)
                prefix_length += 1
            end
            prefix = row[1:prefix_length]
            created = fresh_name(lhs,g.rules)
            g.rules[created] = [current[i][prefix_length+1:end] for i in group]
            current = [i==group[1] ? vcat(
                prefix,
                [created]
            ) : alternative for (i,alternative) in enumerate(current) if i==group[1] || !(i in group)]
            g.rules[lhs] = current
            push!(insertions,created)
            push!(log,"left factor $lhs on $(format_alternative(prefix)) with $created")
            index = group[1]+1
        end
        splice!(g.order,position+1:position,insertions)
        position += 1
    end
    g,log
end
