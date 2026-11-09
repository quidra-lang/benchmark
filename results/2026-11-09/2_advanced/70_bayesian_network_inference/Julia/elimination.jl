function interaction_graph(factors)
    graph = Dict{Int,Set{Int}}()
    for factor in factors
        for v in factor.variables
            get!(graph,v,Set{Int}())
        end
        for v in factor.variables,u in factor.variables
            v!=u && push!(graph[v],u)
        end
    end
    graph
end
function make_plan(factors,eliminate,method,given_order,sizes)
    graph = interaction_graph(factors)
    remaining,steps = Set(eliminate),NamedTuple[]
    ranks = Dict(v=>i for (i,v) in enumerate(given_order))
    while !isempty(remaining)
        fills = Dict{Int,Int}()
        for v in remaining
            neighbors = sort!(collect(graph[v]))
            fills[v] = sum((!(neighbors[j] in graph[neighbors[i]]) for i in eachindex(neighbors) for j in i+1:length(neighbors));init=0)
        end
        v = method=="MINFILL" ? argmin(
            v->(fills[v],length(graph[v]),v),
            remaining
        ) : argmin(v->ranks[v],remaining)
        neighbors = sort!(collect(graph[v]))
        scope = sort!([v;neighbors])
        push!(steps,(variable=v,fill=fills[v],scope=scope,size=entry_count(scope,sizes)))
        for left in neighbors,right in neighbors
            left!=right && push!(graph[left],right)
        end
        for neighbor in neighbors
            delete!(graph[neighbor],v)
        end
        delete!(graph,v)
        delete!(remaining,v)
    end
    (steps=steps,maximum=maximum((s.size for s in steps);init=0),total=sum((s.size for s in steps);init=0))
end
function execute_plan(initial,plan,sizes,maximize=false)
    factors,products = copy(initial),Tuple{Int,Factor}[]
    for step in plan.steps
        selected = [f for f in factors if step.variable in f.variables]
        factors = [f for f in factors if !(step.variable in f.variables)]
        product = multiply_factors(selected,sizes)
        push!(factors,eliminate_factor(product,step.variable,sizes,maximize))
        maximize && push!(products,(step.variable,product))
    end
    multiply_factors(factors,sizes),products
end
function traceback(products,sizes)
    assignment = zeros(Int,length(sizes))
    for (v,product) in reverse(products)
        candidates = Float64[]
        for state in 1:sizes[v]
            assignment[v] = state
            push!(candidates,factor_value(product,assignment,sizes))
        end
        assignment[v] = argmax(candidates)
    end
    assignment
end
