function run_round(variable_count,search_clauses)
    clauses = deepcopy(search_clauses)
    assignment = zeros(Int8,variable_count)
    watches = Dict{Int,Vector{Int}}()
    trail = Tuple{Int,String}[]
    queue_head = 1
    trace = String[]
    stats = Dict("decisions"=>0,"propagations"=>0,"conflicts"=>0,"max_depth"=>0)
    value(literal) = literal > 0 ? assignment[abs(literal)] : -assignment[abs(literal)]
    function assign!(literal,kind)
        assignment[abs(literal)] = literal > 0 ? 1 : -1
        push!(trail,(literal,kind))
        push!(trace,kind*string(literal))
    end
    function conflict!()
        stats["conflicts"] += 1
        push!(trace,"C")
    end
    for (index,clause) in enumerate(clauses)
        if length(clause) >= 2
            push!(get!(()->Int[],watches,clause[1]),index)
            push!(get!(()->Int[],watches,clause[2]),index)
        end
    end
    for clause in clauses
        if isempty(clause)
            conflict!()
            return nothing,trace,stats
        elseif length(clause) == 1
            literal = only(clause)
            if value(literal) == -1
                conflict!()
                return nothing,trace,stats
            elseif value(literal) == 0
                assign!(literal,"P")
                stats["propagations"] += 1
            end
        end
    end
    while true
        found_conflict = false
        while queue_head <= length(trail)
            true_literal = trail[queue_head][1]
            queue_head += 1
            false_literal = -true_literal
            watch_list = get!(()->Int[],watches,false_literal)
            index = 1
            while index <= length(watch_list)
                clause_id = watch_list[index]
                clause = clauses[clause_id]
                clause[1] == false_literal && ((clause[1],clause[2])=(clause[2],clause[1]))
                other = clause[1]
                if value(other) == 1
                    index += 1
                    continue
                end
                substitute = findfirst(j->value(clause[j]) != -1,3:length(clause))
                if !isnothing(substitute)
                    j = substitute+2
                    clause[2],clause[j] = clause[j],clause[2]
                    deleteat!(watch_list,index)
                    push!(get!(()->Int[],watches,clause[2]),clause_id)
                    continue
                end
                if value(other) == -1
                    conflict!()
                    found_conflict = true
                    break
                elseif value(other) == 0
                    assign!(other,"P")
                    stats["propagations"] += 1
                end
                index += 1
            end
            found_conflict && break
        end
        if found_conflict
            while !isempty(trail) && trail[end][2] != "D"
                literal,_ = pop!(trail)
                assignment[abs(literal)] = 0
            end
            isempty(trail) && return nothing,trace,stats
            decision,_ = pop!(trail)
            assignment[abs(decision)] = 0
            assign!(-decision,"F")
            queue_head = length(trail)
            continue
        end
        counts = Dict{Int,Int}()
        for clause in clauses
            any(value(literal) == 1 for literal in clause) && continue
            for literal in clause
                value(literal) == 0 && (counts[literal]=get(counts,literal,0)+1)
            end
        end
        isempty(counts) && return assignment .== 1,trace,stats
        best = first(sort(collect(keys(counts)),by=literal->(-counts[literal],abs(literal),literal < 0)))
        assign!(best,"D")
        stats["decisions"] += 1
        depth = count(pair->pair[2] in ("D","F"),trail)
        stats["max_depth"] = max(stats["max_depth"],depth)
    end
end
