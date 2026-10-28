triangle_edges(vertices) = ((vertices[1],vertices[2]),(vertices[2],vertices[3]),(vertices[3],vertices[1]))
key_edge(a,b) = minmax(a,b)
function edge_table(faces)
    edges = Dict{Tuple{Int,Int},Vector{Int}}()
    for (index,face) in enumerate(faces), (u,v) in triangle_edges(face.vertices)
        push!(get!(()->Int[],edges,key_edge(u,v)),index)
    end
    edges
end
function connected_components(faces,edges)
    neighbors = [Set{Int}() for _ in faces]
    for adjacent in values(edges), face in adjacent, other in adjacent
        other != face && push!(neighbors[face],other)
    end
    unseen = Set(eachindex(faces))
    components = Vector{Int}[]
    while !isempty(unseen)
        seed = minimum(unseen)
        delete!(unseen,seed)
        queue = [seed]
        index = 1
        while index <= length(queue)
            face = queue[index]
            index += 1
            for neighbor in sort(collect(neighbors[face]))
                if neighbor in unseen
                    delete!(unseen,neighbor)
                    push!(queue,neighbor)
                end
            end
        end
        push!(components,sort(queue))
    end
    components
end
function vertex_fans(vertex,faces,edges)
    containing = findall(face->vertex in face.vertices,faces)
    others = Set(containing)
    neighbors = [Set{Int}() for _ in faces]
    for (edge,participating) in edges
        vertex in edge || continue
        for first in participating, second in participating
            first != second && push!(neighbors[first],second)
        end
    end
    fans = Vector{Int}[]
    while !isempty(others)
        seed = minimum(others)
        delete!(others,seed)
        queue = [seed]
        index = 1
        while index <= length(queue)
            face = queue[index]
            index += 1
            for adjacent in sort(collect(neighbors[face]))
                if adjacent in others
                    delete!(others,adjacent)
                    push!(queue,adjacent)
                end
            end
        end
        push!(fans,sort(queue))
    end
    fans
end
function analyze_mesh(faces)
    edges = edge_table(faces)
    edge_order = sort(collect(keys(edges)))
    components = Dict{Symbol,Any}[]
    face_components = zeros(Int,length(faces))
    for (number,ids) in enumerate(connected_components(faces,edges))
        face_components[ids] .= number
        vertices = sort(unique([v for id in ids for v in faces[id].vertices]))
        component_edges = [edge for edge in edge_order if any(face in ids for face in edges[edge])]
        push!(
            components,
            record(
                number=number,
                faces=ids,
                vertices=vertices,
                edges=component_edges,
                boundary=filter(edge->length(edges[edge]) == 1,component_edges),
                nonmanifold=filter(edge->length(edges[edge]) >= 3,component_edges)
            )
        )
    end
    used = sort(unique([v for face in faces for v in face.vertices]))
    fans = Dict(v=>vertex_fans(v,faces,edges) for v in used)
    nonmanifold_vertices = [v for v in used if length(fans[v]) >= 2]
    for component in components
        number = component[:number]
        component[:nonmanifold_vertices] = [v for v in component[:vertices] if count(
            fan->any(face_components[f] == number for f in fan),
            fans[v]
        ) >= 2]
    end
    (
        edges=edges,
        edge_order=edge_order,
        components=components,
        face_components=face_components,
        fans=fans,
        nonmanifold_vertices=nonmanifold_vertices
    )
end
function boundary_loops(faces,mesh,contains_directed)
    loops = Dict{Symbol,Any}[]
    for component in mesh.components
        unused = Set(component[:boundary])
        for first_edge in component[:boundary]
            first_edge in unused || continue
            delete!(unused,first_edge)
            a,b = first_edge
            sequence = [a,b]
            current = b
            while current != a
                choices = [(u == current ? v : u,(u,v)) for (u,v) in unused if current in (u,v)]
                isempty(choices) && break
                other,chosen = minimum(choices)
                delete!(unused,chosen)
                push!(sequence,other)
                current = other
            end
            closed = last(sequence) == a
            kind = "open"
            count = length(sequence)-1
            if closed
                pop!(sequence)
                count = length(sequence)
                directed = [contains_directed(
                    faces[only(mesh.edges[key_edge(sequence[i],sequence[mod1(i+1,count)])])].vertices,
                    sequence[i],
                    sequence[mod1(i+1,count)]
                ) for i in 1:count]
                if all(directed)
                    kind = "coherent"
                elseif !any(directed)
                    kind = "coherent"
                    sequence = vcat(sequence[1:1],reverse(sequence[2:end]))
                else
                    kind = "mixed"
                end
            end
            push!(
                loops,
                record(
                    number=length(loops)+1,
                    component=component[:number],
                    vertices=sequence,
                    length=count,
                    kind=kind,
                    filled=false
                )
            )
        end
    end
    loops
end
