function root!(parents, vertex)
    while parents[vertex] != vertex
        parents[vertex] = parents[parents[vertex]]
        vertex = parents[vertex]
    end
    return vertex
end

function main()
    edges = [
        ('A', 'B', 7),
        ('C', 'A', 4),
        ('B', 'C', 9),
        ('B', 'D', 14),
        ('D', 'C', 6),
        ('C', 'E', 3),
        ('E', 'D', 5),
        ('F', 'D', 11),
        ('E', 'G', 16),
        ('G', 'F', 8),
        ('H', 'F', 12),
        ('G', 'H', 2),
        ('H', 'E', 10),
    ]
    sort!(edges; by = edge -> edge[3])
    parents = collect(1:8)
    accepted, skipped, total = 0, 0, 0
    for (a, b, weight) in edges
        first_root = root!(parents, Int(a)-Int('A')+1)
        second_root = root!(parents, Int(b)-Int('A')+1)
        if first_root == second_root
            skipped += 1
        else
            parents[second_root] = first_root
            accepted += 1
            total += weight
            println(min(a, b), '-', max(a, b), " ", weight)
            accepted == 7 && break
        end
    end
    println("total weight: ", total)
    println("skipped: ", skipped)
end

main()
