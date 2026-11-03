has_directed(triangle,start,stop) = (start,stop) in triangle_edges(triangle)
flip!(face) = (face.vertices=(face.vertices[1],face.vertices[3],face.vertices[2]))
function inconsistent_edges(faces,edges)
    result = Tuple{Int,Int}[]
    for edge in sort(collect(keys(edges)))
        adjacent = edges[edge]
        length(adjacent) != 2 && continue
        has_directed(faces[adjacent[1]].vertices,edge...) == has_directed(
            faces[adjacent[2]].vertices,
            edge...
        ) && push!(result,edge)
    end
    result
end
function repair_orientation!(faces,edges)
    visited = falses(length(faces))
    for seed in eachindex(faces)
        visited[seed] && continue
        visited[seed] = true
        queue = [seed]
        index = 1
        while index <= length(queue)
            current = queue[index]
            index += 1
            for (u,v) in triangle_edges(faces[current].vertices)
                adjacent = edges[key_edge(u,v)]
                length(adjacent) == 2 || continue
                other = adjacent[1] == current ? adjacent[2] : adjacent[1]
                visited[other] && continue
                has_directed(faces[other].vertices,u,v) && flip!(faces[other])
                visited[other] = true
                push!(queue,other)
            end
        end
    end
end
function orientable_components(faces,mesh)
    copied = deepcopy(faces)
    repair_orientation!(copied,mesh.edges)
    violations = Set(inconsistent_edges(copied,mesh.edges))
    [!any(edge in violations for edge in component[:edges]) for component in mesh.components]
end
