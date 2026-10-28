entry_count(variables,sizes) = prod((sizes[v] for v in variables);init=1)
function canonical_assignment(index,variables,sizes)
    assignment = zeros(Int,length(sizes))
    for v in reverse(variables)
        assignment[v] = index%sizes[v]+1
        index ÷= sizes[v]
    end
    assignment
end
assignments(variables,sizes) = (canonical_assignment(
    i,
    variables,
    sizes
) for i in 0:entry_count(variables,sizes)-1)
struct Factor
    variables::Vector{Int}
    entries::Vector{Float64}
end
factor_value(factor,assignment,sizes) = factor.entries[parent_row(factor.variables,assignment,sizes)]
function reduce_factor(factor,evidence,sizes)
    variables = [v for v in factor.variables if !haskey(evidence,v)]
    entries = Float64[]
    for assignment in assignments(variables,sizes)
        for (v,s) in evidence
            assignment[v] = s
        end
        push!(entries,factor_value(factor,assignment,sizes))
    end
    Factor(variables,entries)
end
function product_factor(left,right,sizes)
    variables = sort!(union(left.variables,right.variables))
    Factor(
        variables,
        [factor_value(left,a,sizes)*factor_value(right,a,sizes) for a in assignments(variables,sizes)]
    )
end
function eliminate_factor(factor,v,sizes,maximize=false)
    variables = filter(!=(v),factor.variables)
    entries = Float64[]
    for assignment in assignments(variables,sizes)
        candidates = Float64[]
        for s in 1:sizes[v]
            assignment[v] = s
            push!(candidates,factor_value(factor,assignment,sizes))
        end
        push!(entries,maximize ? maximum(candidates) : ordered_total(candidates))
    end
    Factor(variables,entries)
end
function cpt_factor(v,parents,cpt,sizes)
    variables = sort!([v;parents])
    Factor(variables,[cpt[parent_row(parents,a,sizes),a[v]] for a in assignments(variables,sizes)])
end
function multiply_factors(factors,sizes)
    isempty(factors) && return Factor(Int[],[1.0])
    result = factors[1]
    for factor in factors[2:end]
        result = product_factor(result,factor,sizes)
    end
    result
end
