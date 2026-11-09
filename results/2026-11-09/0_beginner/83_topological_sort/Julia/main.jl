function topological(courses, edges)
    indegree = Dict(course=>0 for course in courses)
    adjacency = Dict(course=>String[] for course in courses)
    for (source, target) in edges
        push!(adjacency[source], target)
        indegree[target] += 1
    end
    ordered = String[]
    taken = Set{String}()
    alphabetical = sort(courses)
    while true
        index =
            findfirst(course -> !(course in taken) && indegree[course] == 0, alphabetical)
        index === nothing && break
        course = alphabetical[index]
        push!(ordered, course)
        push!(taken, course)
        for target in adjacency[course]
            indegree[target] -= 1
        end
    end
    return ordered, setdiff(alphabetical, ordered)
end

courses1 = [
    "physics",
    "algebra",
    "graphics",
    "programming",
    "statistics",
    "calculus",
    "databases",
    "algorithms",
]
edges1 = [
    ("calculus", "physics"),
    ("algebra", "calculus"),
    ("programming", "algorithms"),
    ("algebra", "statistics"),
    ("algorithms", "databases"),
    ("statistics", "databases"),
    ("calculus", "graphics"),
    ("algorithms", "graphics"),
    ("physics", "graphics"),
]
courses2 = ["music", "ecology", "art", "geology", "biology", "chemistry"]
edges2 = [
    ("music", "art"),
    ("art", "ecology"),
    ("biology", "chemistry"),
    ("chemistry", "ecology"),
    ("ecology", "geology"),
    ("geology", "chemistry"),
]
order1, _ = topological(courses1, edges1)
order2, remaining = topological(courses2, edges2)
println("order: ", join(order1, " -> "))
println("order: ", join(order2, " -> "))
println("cycle: ", join(remaining, " "))
