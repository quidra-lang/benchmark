function dfs!(vertex,adjacency,visited,order)
    visited[vertex+1] = true
    push!(order,vertex)
    for neighbor in adjacency[vertex+1]
        !visited[neighbor+1] && dfs!(neighbor,adjacency,visited,order)
    end
end
function main()
    adjacency = [Int[] for vertex in 0:8]
    for (a,b) in [(5,0),(3,8),(7,2),(1,6),(0,2),(5,3),(7,5),(6,4),(8,7)]
        push!(adjacency[a+1],b)
        push!(adjacency[b+1],a)
    end
    foreach(sort!,adjacency)
    order = Int[]
    dfs!(0,adjacency,falses(9),order)
    println("DFS: ",join(order," "))
    queue,visited = [0],falses(9)
    visited[1] = true
    head = 1
    while head <= length(queue)
        vertex = queue[head]
        head += 1
        for neighbor in adjacency[vertex+1]
            if !visited[neighbor+1]
                visited[neighbor+1] = true
                push!(queue,neighbor)
            end
        end
    end
    println("BFS: ",join(queue," "))
    components = Vector{Int}[]
    visited .= false
    for vertex in 0:8
        if !visited[vertex+1]
            component = Int[]
            dfs!(vertex,adjacency,visited,component)
            push!(components,sort(component))
        end
    end
    println("components: ",length(components))
    for (number,component) in enumerate(components)
        println("component ",number,": ",join(component," "))
    end
end
main()
