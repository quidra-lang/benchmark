function preprocess(variables,original,use_pure)
    working = Tuple{Int,Vector{Int}}[]
    records = Dict(kind=>Int[] for kind in ("tautology","unit","subsumed","pure"))
    counts = Dict(kind=>0 for kind in (
        "tautologies",
        "duplicate_literals",
        "unit_fixed",
        "unit_removed",
        "subsumed",
        "pure_fixed",
        "pure_removed"
    ))
    fixed = Dict{Int,Bool}()
    for (number,clause) in enumerate(original)
        present = Set(clause)
        if any(-literal in present for literal in clause)
            counts["tautologies"] += 1
            push!(records["tautology"],number)
            continue
        end
        reduced = unique(clause)
        counts["duplicate_literals"] += length(clause)-length(reduced)
        push!(working,(number,reduced))
    end
    empty_clause = nothing
    while true
        empty_index = findfirst(pair->isempty(pair[2]),working)
        if !isnothing(empty_index)
            empty_clause = working[empty_index][1]
            break
        end
        unit_index = findfirst(pair->length(pair[2]) == 1,working)
        isnothing(unit_index) && break
        unit = only(working[unit_index][2])
        fixed[abs(unit)] = unit > 0
        counts["unit_fixed"] += 1
        surviving = Tuple{Int,Vector{Int}}[]
        for (number,clause) in working
            if unit in clause
                push!(records["unit"],number)
                counts["unit_removed"] += 1
            else
                push!(surviving,(number,filter(!=(-unit),clause)))
            end
        end
        working = surviving
    end
    if isnothing(empty_clause)
        before = working
        removed = falses(length(before))
        for (ib,(_,b)) in enumerate(before)
            bset = Set(b)
            for (ia,(_,a)) in enumerate(before)
                ia == ib && continue
                if issubset(Set(a),bset) && (length(a) < length(b) || ia < ib)
                    removed[ib] = true
                    break
                end
            end
        end
        working = before[.!removed]
        records["subsumed"] = [before[i][1] for i in eachindex(before) if removed[i]]
        counts["subsumed"] = count(removed)
        if use_pure
            while true
                present = Set(literal for (_,clause) in working for literal in clause)
                pure = Set(literal for literal in present if !(-literal in present))
                isempty(pure) && break
                for literal in pure
                    fixed[abs(literal)] = literal > 0
                end
                counts["pure_fixed"] += length(pure)
                remaining = Tuple{Int,Vector{Int}}[]
                for (number,clause) in working
                    if any(literal in pure for literal in clause)
                        push!(records["pure"],number)
                        counts["pure_removed"] += 1
                    else
                        push!(remaining,(number,clause))
                    end
                end
                working = remaining
            end
        end
    end
    counts["removed"] = sum(counts[key] for key in ("tautologies","unit_removed","subsumed","pure_removed"))
    foreach(sort!,values(records))
    (
        clauses=[clause for (
            _,
            clause
        ) in working],fixed=fixed,active=[v for v in 1:variables if !haskey(fixed,v)],
        counts=counts,records=records,empty_clause=empty_clause,pure=use_pure
    )
end
