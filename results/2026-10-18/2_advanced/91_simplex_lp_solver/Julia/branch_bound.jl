struct BranchNode
    lower::Vector{Union{Nothing,Fraction}}
    upper::Vector{Union{Nothing,Fraction}}
    depth::Int
    parent::Union{Nothing,Int}
    branch::String
    parent_value::Union{Nothing,Fraction}
end
function branch_search(model,limit,solve)
    stack = [BranchNode(copy(model.lower),copy(model.upper),0,nothing,"root",nothing)]
    solves,lines = Any[],String[]
    incumbent,objective,status = nothing,nothing,nothing
    incumbents,pruned,infeasible = 0,0,0
    while !isempty(stack)
        if length(solves) == limit
            status = "NODE_LIMIT"
            break
        end
        node = pop!(stack)
        number = length(solves)+1
        result = solve(node.lower,node.upper,number)
        push!(solves,result)
        if result.status == "INFEASIBLE"
            outcome = "infeasible"
            infeasible += 1
        elseif result.status == "UNBOUNDED"
            outcome,status = "unbounded","UNBOUNDED"
        elseif objective !== nothing && (model.direction == "maximize" ? result.objective <= objective : result.objective >= objective)
            outcome = "pruned"
            pruned += 1
        else
            fractional = findfirst(j -> model.integer[j] && denominator(result.solution[j]) != 1,eachindex(model.variables))
            if fractional === nothing
                incumbent,objective = copy(result.solution),result.objective
                outcome = "incumbent"
                incumbents += 1
            else
                value,name = result.solution[fractional],model.variables[fractional]
                down,up = floor(Int64,value),ceil(Int64,value)
                lower,upper = copy(node.lower),copy(node.upper)
                lower[fractional],upper[fractional] = Fraction(up),Fraction(down)
                push!(stack,BranchNode(lower,copy(node.upper),node.depth+1,number,"$name>=$up",result.objective))
                push!(stack,BranchNode(copy(node.lower),upper,node.depth+1,number,"$name<=$down",result.objective))
                outcome = "branch $name $(fraction_text(value))"
            end
        end
        parent = node.parent === nothing ? "-" : string(node.parent)
        lp = result.status == "OPTIMAL" ? fraction_text(result.objective) : lowercase(result.status)
        push!(lines,"NODE $number depth $(node.depth) parent $parent branch $(node.branch) lp $lp pivots $(result.pivots) action $outcome")
        status == "UNBOUNDED" && break
    end
    status === nothing && (status = incumbent === nothing ? "INFEASIBLE" : "OPTIMAL")
    if status == "NODE_LIMIT"
        for node in reverse(stack)
            push!(lines,"OPEN parent $(node.parent) branch $(node.branch) bound $(fraction_text(node.parent_value))")
        end
        bounds = Fraction[node.parent_value for node in stack]
        objective === nothing || push!(bounds,objective)
        bound = model.direction == "maximize" ? maximum(bounds) : minimum(bounds)
    else
        bound = objective
    end
    push!(lines,"RESULT $status objective $(shown(objective)) nodes $(length(solves)) incumbents $incumbents pruned $pruned infeasible $infeasible open $(length(stack)) bound $(shown(bound))")
    (;status,objective,solution=incumbent,solves,root=solves[1],lines,nodes=length(solves))
end
