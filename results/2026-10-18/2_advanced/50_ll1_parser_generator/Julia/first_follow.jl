terminal_order(terms) = vcat(
    sort([t for t in terms if t!=END_MARKER]),
    END_MARKER in terms ? [END_MARKER] : String[]
)
terminals_of(g) = Set(s for lhs in g.order for rhs in g.rules[lhs] for s in rhs if !is_nonterminal(s))
function first_sequence(rhs,nullable,firsts)
    found = Set{String}()
    for symbol in rhs
        if !is_nonterminal(symbol)
            push!(found,symbol)
            return found,false
        end
        union!(found,firsts[symbol])
        nullable[symbol] || return found,false
    end
    found,true
end
function analyze_sets(g)
    nullable = Dict(lhs=>false for lhs in g.order)
    firsts,follow = Dict(lhs=>Set{String}() for lhs in g.order),Dict(lhs=>Set{String}() for lhs in g.order)
    push!(follow[g.start],END_MARKER)
    passes = Dict{String,Int}()
    for kind in ("nullable","first","follow")
        count = 0
        while true
            count += 1
            changed = false
            for lhs in g.order
                if kind=="nullable"
                    if !nullable[lhs] && any(rhs->all(s->is_nonterminal(s) && nullable[s],rhs),g.rules[lhs])
                        nullable[lhs] = true
                        changed = true
                    end
                else
                    for rhs in g.rules[lhs]
                        if kind=="first"
                            more,_ = first_sequence(rhs,nullable,firsts)
                            if !issubset(more,firsts[lhs])
                                union!(firsts[lhs],more)
                                changed = true
                            end
                        else
                            for (i,symbol) in enumerate(rhs)
                                is_nonterminal(symbol) || continue
                                more,empty = first_sequence(rhs[i+1:end],nullable,firsts)
                                empty && union!(more,follow[lhs])
                                if !issubset(more,follow[symbol])
                                    union!(follow[symbol],more)
                                    changed = true
                                end
                            end
                        end
                    end
                end
            end
            changed || break
        end
        passes[kind] = count
    end
    (nullable=nullable,first=firsts,follow=follow,passes=passes,terminals=terminal_order(terminals_of(g)))
end
