struct TACAllocation
    neighbors::Dict{String,Set{String}}
    costs::Dict{String,BigInt}
    partners::Dict{String,Set{String}}
    order::Vector{String}
    potential::Vector{Tuple{String,Int}}
    colors::Dict{String,Int}
    spills::Set{String}
end
function add_edge!(neighbors,first,second)
    push!(neighbors[first],second)
    push!(neighbors[second],first)
end
function TACAllocation(function_node,graph,flow,registers)
    nodes = Set(function_node.parameters)
    for (number,entry) in enumerate(graph.instructions)
        graph.block_of[number] in graph.reachable || continue
        union!(nodes,used_variables(entry))
        entry.destination !== nothing && push!(nodes,entry.destination)
    end
    neighbors = Dict(node=>Set{String}() for node in nodes)
    costs = Dict(node=>BigInt(0) for node in nodes)
    partners = Dict(node=>Set{String}() for node in nodes)
    for block_number in graph.reachable
        block = graph.blocks[block_number]
        state = copy(flow.live_out[block_number])
        for number in reverse(block.instructions)
            entry = graph.instructions[number]
            destination = entry.destination
            if destination !== nothing
                partner = entry.kind == "copy" ? entry.a : nothing
                for variable in state
                    variable != destination && variable != partner && add_edge!(neighbors,destination,variable)
                end
            end
            state = live_transfer(entry,state)
        end
        weight = big(10)^graph.depth[block_number]
        for number in block.instructions
            entry = graph.instructions[number]
            occurrences = used_variables(entry)
            entry.destination !== nothing && push!(occurrences,entry.destination)
            for variable in occurrences
                costs[variable] += weight
            end
        end
    end
    entry = union(flow.live_in[1],Set(function_node.parameters))
    for parameter in function_node.parameters
        costs[parameter] += 1
        for variable in setdiff(entry,Set([parameter]))
            add_edge!(neighbors,parameter,variable)
        end
    end
    for entry in instructions(function_node)
        if entry.kind == "copy" && entry.a isa String && entry.destination != entry.a
            haskey(partners,entry.destination) && push!(partners[entry.destination],entry.a)
            haskey(partners,entry.a) && push!(partners[entry.a],entry.destination)
        end
    end
    order,potential = String[],Tuple{String,Int}[]
    remaining = copy(nodes)
    while !isempty(remaining)
        degrees = Dict(node=>length(intersect(neighbors[node],remaining)) for node in remaining)
        simple = filter(node->degrees[node] < registers,collect(remaining))
        if !isempty(simple)
            chosen = argmin(node->(degrees[node],node),simple)
        else
            candidates = sort(collect(remaining))
            chosen = candidates[1]
            for node in candidates[2:end]
                costs[node]*degrees[chosen] < costs[chosen]*degrees[node] && (chosen = node)
            end
            push!(potential,(chosen,degrees[chosen]))
        end
        push!(order,chosen)
        delete!(remaining,chosen)
    end
    colors = Dict{String,Int}()
    for node in reverse(order)
        occupied = Set(get(colors,neighbor,-1) for neighbor in neighbors[node])
        free = setdiff(Set(0:registers-1),occupied)
        if isempty(free)
            colors[node] = -1
        else
            preferred = intersect(Set(get(colors,partner,-1) for partner in partners[node]),free)
            colors[node] = minimum(isempty(preferred) ? free : preferred)
        end
    end
    spills = Set(node for (node,color) in colors if color == -1)
    TACAllocation(neighbors,costs,partners,order,potential,colors,spills)
end
