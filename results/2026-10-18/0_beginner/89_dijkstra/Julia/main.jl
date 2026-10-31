function main()
    names = collect("ABCDEFG")
    weights = zeros(Int, 7, 7)
    edges = [
        ('A', 'B', 7),
        ('A', 'C', 3),
        ('A', 'D', 9),
        ('B', 'C', 2),
        ('C', 'E', 6),
        ('B', 'D', 3),
        ('D', 'E', 4),
        ('D', 'F', 5),
        ('E', 'F', 3),
        ('E', 'G', 8),
        ('F', 'G', 4),
    ]
    for (a, b, weight) in edges
        i, j = Int(a)-Int('A')+1, Int(b)-Int('A')+1
        weights[i, j] = weights[j, i] = weight
    end
    distance = fill(typemax(Int), 7)
    previous = zeros(Int, 7)
    finalized = falses(7)
    distance[1] = 0
    for step = 1:7
        vertex = argmin(i -> distance[i], findall(!, finalized))
        finalized[vertex] = true
        for neighbor = 1:7
            if weights[vertex, neighbor] > 0 &&
               distance[vertex]+weights[vertex, neighbor] < distance[neighbor]
                distance[neighbor] = distance[vertex]+weights[vertex, neighbor]
                previous[neighbor] = vertex
            end
        end
    end
    for i = 1:7
        path = Char[]
        vertex = i
        while vertex != 0
            pushfirst!(path, names[vertex])
            vertex = previous[vertex]
        end
        println(names[i], ": distance=", distance[i], " path=", join(path, "-"))
    end
end

main()
