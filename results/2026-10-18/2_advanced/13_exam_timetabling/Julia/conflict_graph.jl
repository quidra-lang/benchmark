struct ConflictGraph
    vertices::Vector{String}
    shared::Dict{String,Dict{String,Int}}
end

function ConflictGraph(vertices, student_courses)
    vertices = sort(collect(vertices))
    shared = Dict(id => Dict{String,Int}() for id in vertices)
    for ids in student_courses
        for i in eachindex(ids), j in i + 1:length(ids)
            first, second = ids[i], ids[j]
            shared[first][second] = get(shared[first], second, 0) + 1
            shared[second][first] = get(shared[second], first, 0) + 1
        end
    end
    ConflictGraph(vertices, shared)
end

neighbours(graph, id) = get(graph.shared, id, Dict{String,Int}())
degree(graph, id) = length(neighbours(graph, id))
shared_total(graph, id) = sum(values(neighbours(graph, id)); init=0)
graph_edges(graph) = [(first, second, graph.shared[first][second]) for first in graph.vertices for second in sort(collect(keys(graph.shared[first]))) if first < second]

function components(graph)
    seen = Set{String}()
    result = Vector{String}[]
    for vertex in graph.vertices
        vertex in seen && continue
        push!(seen, vertex)
        component = [vertex]
        index = 1
        while index <= length(component)
            for other in keys(neighbours(graph, component[index]))
                if !(other in seen)
                    push!(seen, other)
                    push!(component, other)
                end
            end
            index += 1
        end
        push!(result, sort!(component))
    end
    sort!(result; by=group -> (-length(group), first(group)))
end

function greedy_clique(graph, candidates)
    candidates = copy(candidates)
    result = String[]
    while !isempty(candidates)
        chosen = first(sort(candidates; by=id -> (-degree(graph, id), id)))
        push!(result, chosen)
        filter!(id -> haskey(neighbours(graph, chosen), id), candidates)
    end
    result
end

function kempe_chain(graph, assignment, start, home, target)
    chain = [start]
    seen = Set(chain)
    index = 1
    while index <= length(chain)
        for other in keys(neighbours(graph, chain[index]))
            if !(other in seen) && get(assignment, other, 0) in (home, target)
                push!(seen, other)
                push!(chain, other)
            end
        end
        index += 1
    end
    sort!(chain)
end

function reachable(arrows, source, target)
    stack = [source]
    seen = Set(stack)
    while !isempty(stack)
        node = pop!(stack)
        node == target && return true
        for other in get(arrows, node, String[])
            if !(other in seen)
                push!(seen, other)
                push!(stack, other)
            end
        end
    end
    false
end
