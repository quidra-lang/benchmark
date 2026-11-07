function main()
    cache = Char[]
    hits, misses = 0, 0
    for key in ['B', 'A', 'C', 'B', 'D', 'A', 'B', 'E', 'A', 'D', 'D', 'C', 'A', 'E', 'B']
        index = findfirst(==(key), cache)
        if index !== nothing
            hits += 1
            deleteat!(cache, index)
            result = "hit"
        else
            misses += 1
            result = length(cache) == 3 ? string("miss, evict ", pop!(cache)) : "miss"
        end
        pushfirst!(cache, key)
        println(key, ": ", result, " [", join(cache, " "), "]")
    end
    println("hits: ", hits, " misses: ", misses)
end

main()
