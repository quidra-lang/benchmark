function number_productions(g)
    productions = NamedTuple[]
    for lhs in g.order,rhs in g.rules[lhs]
        push!(
            productions,
            (
                number=length(productions)+1,
                lhs=lhs,
                rhs=rhs,
                notation=format_production(lhs,rhs),
                predict=Dict{String,String}()
            )
        )
    end
    productions
end
function build_table(g,sets)
    productions = number_productions(g)
    cells = Dict((lhs,t)=>NamedTuple[] for lhs in g.order for t in vcat(sets.terminals,[END_MARKER]))
    for p in productions
        direct,empty = first_sequence(p.rhs,sets.nullable,sets.first)
        for t in direct
            p.predict[t] = "FIRST"
        end
        if empty
            for t in sets.follow[p.lhs]
                get!(p.predict,t,"FOLLOW")
            end
        end
        for t in terminal_order(keys(p.predict))
            push!(cells[(p.lhs,t)],(number=p.number,reason=p.predict[t]))
        end
    end
    choices = Dict{Tuple{String,String},Int}()
    conflicts = NamedTuple[]
    for lhs in g.order,t in vcat(sets.terminals,[END_MARKER])
        entries = cells[(lhs,t)]
        isempty(entries) && continue
        preferred = findfirst(entry->entry.reason=="FIRST",entries)
        choice = entries[isnothing(preferred) ? 1 : preferred].number
        choices[(lhs,t)] = choice
        if length(entries)>=2
            reasons = Set(entry.reason for entry in entries)
            kind = reasons==Set(["FIRST"]) ? "FIRST/FIRST" : reasons==Set(["FOLLOW"]) ? "FOLLOW/FOLLOW" : "FIRST/FOLLOW"
            push!(conflicts,(lhs=lhs,token=t,kind=kind,entries=entries,chosen=choice))
        end
    end
    (productions=productions,cells=cells,choices=choices,conflicts=conflicts)
end
