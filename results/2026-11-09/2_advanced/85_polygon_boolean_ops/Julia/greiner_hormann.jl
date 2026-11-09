mutable struct GHNode
    point::Point
    side::Int
    crossing::Int
    next::Int
    previous::Int
    other::Int
    entering::Bool
end
function build_graph(first,second)
    sequences = [first,second]
    slots = [[[Any[] for _ in ring] for ring in sequence] for sequence in sequences]
    nodes = GHNode[]
    crossing_count = 0
    for (ri,ring) in enumerate(first), (ei,(a,b)) in enumerate(ring_edges(ring))
        for (rj,other) in enumerate(second), (ej,(c,d)) in enumerate(ring_edges(other))
            found = edge_crossing(a,b,c,d)
            found === nothing && continue
            crossing_count += 1
            i,j = length(nodes)+1,length(nodes)+2
            push!(nodes, GHNode(found.point,1,crossing_count,0,0,j,false))
            push!(nodes, GHNode(found.point,2,crossing_count,0,0,i,false))
            push!(slots[1][ri][ei],(position=found.t,node=i))
            push!(slots[2][rj][ej],(position=found.u,node=j))
        end
    end
    ring_nodes, initial = [Vector{Int}[] for _ in 1:2], [Bool[] for _ in 1:2]
    for side in 1:2
        for (ri,ring) in enumerate(sequences[side])
            listed = Int[]
            for (ei,p) in enumerate(ring)
                push!(nodes,GHNode(p,side,0,0,0,0,false))
                push!(listed,length(nodes))
                append!(listed,[slot.node for slot in sort(slots[side][ri][ei];by=s -> s.position)])
            end
            state = interior(sequences[3-side],ring[1])
            push!(initial[side],state)
            for (i,id) in enumerate(listed)
                nodes[id].previous = listed[mod1(i-1,length(listed))]
                nodes[id].next = listed[mod1(i+1,length(listed))]
                if nodes[id].crossing != 0
                    nodes[id].entering = !state
                    state = !state
                end
            end
            push!(ring_nodes[side],listed)
        end
    end
    crossings = [id for listed in ring_nodes[1] for id in listed if nodes[id].crossing != 0]
    return (
        sequences=sequences,
        nodes=nodes,
        ring_nodes=ring_nodes,
        initial=initial,
        crossings=crossings,
        n_a=count(initial[1]),
        n_b=count(initial[2])
    )
end
function traverse_graph(graph,invert_first,invert_second)
    inverted = [invert_first,invert_second]
    visited = Set{Int}()
    result = Vector{Point}[]
    for start in graph.crossings
        graph.nodes[start].crossing in visited && continue
        points = Point[]
        current = start
        while true
            node = graph.nodes[current]
            push!(visited,node.crossing)
            push!(points,node.point)
            forward = node.entering != inverted[node.side]
            stopped = forward ? node.next : node.previous
            while graph.nodes[stopped].crossing == 0
                push!(points,graph.nodes[stopped].point)
                stopped = forward ? graph.nodes[stopped].next : graph.nodes[stopped].previous
            end
            graph.nodes[stopped].crossing == graph.nodes[start].crossing && break
            current = graph.nodes[stopped].other
        end
        push!(result,points)
    end
    for side in 1:2, (i,ring) in enumerate(graph.sequences[side])
        any(graph.nodes[id].crossing != 0 for id in graph.ring_nodes[side][i]) && continue
        graph.initial[side][i] != inverted[side] && push!(result,copy(ring))
    end
    return result
end
