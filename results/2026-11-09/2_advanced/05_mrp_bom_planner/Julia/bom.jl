module Bom

struct Edge
    parent::String
    child::String
    quantity::Int
    scrap::Int
end

struct Graph
    children::Dict{String,Vector{Edge}}
    parents::Dict{String,Vector{Edge}}
end

need(edge, quantity) = (quantity * edge.quantity * (100 + edge.scrap) + 99) ÷ 100
manufactured(graph, id) = !isempty(graph.children[id])

function path(graph, id, target, visited)
    id == target && return [id]
    push!(visited, id)
    for edge in graph.children[id]
        edge.child in visited && continue
        rest = path(graph, edge.child, target, visited)
        !isnothing(rest) && return [id; rest]
    end
    return nothing
end

function load(pathname, items, errors)
    graph = Graph(Dict(id => Edge[] for id in keys(items)), Dict(id => Edge[] for id in keys(items)))
    for (number, line) in enumerate(readlines(pathname))
        number == 1 && continue
        fields = String.(split(line, ','))
        parent, child, quantity, scrap = fields[1], fields[2], parse(Int, fields[3]), parse(Int, fields[4])
        message = if !haskey(items, parent)
            "unknown item $parent"
        elseif !haskey(items, child)
            "unknown item $child"
        elseif quantity < 1
            "bad quantity $quantity"
        elseif scrap > 50
            "bad scrap $scrap"
        elseif parent == child
            "cycle $parent -> $parent"
        elseif any(edge -> edge.child == child, graph.children[parent])
            "duplicate $parent -> $child"
        else
            cycle = path(graph, child, parent, Set{String}())
            isnothing(cycle) ? "" : "cycle $parent -> $(join(cycle, " -> "))"
        end
        if !isempty(message)
            push!(errors, "bom.csv line $number: $message")
            continue
        end
        edge = Edge(parent, child, quantity, scrap)
        push!(graph.children[parent], edge)
        sort!(graph.children[parent]; by=edge -> edge.child)
        push!(graph.parents[child], edge)
        sort!(graph.parents[child]; by=edge -> edge.parent)
    end
    return graph
end

function codes(graph, items)
    result = Dict{String,Int}()
    function visit(id)
        return get!(result, id) do
            isempty(graph.parents[id]) ? 0 : maximum(visit(edge.parent) + 1 for edge in graph.parents[id])
        end
    end
    for id in keys(items)
        visit(id)
    end
    return result
end

function cumulative(graph, items)
    result = Dict{String,Int}()
    function visit(id)
        return get!(result, id) do
            items[id].lead + (isempty(graph.children[id]) ? 0 : maximum(visit(edge.child) for edge in graph.children[id]))
        end
    end
    for id in keys(items)
        visit(id)
    end
    return result
end

end
