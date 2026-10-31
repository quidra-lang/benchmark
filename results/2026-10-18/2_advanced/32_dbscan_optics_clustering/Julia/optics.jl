const INF = typemax(Int)
function core_distances(points,neighborhoods,min_pts)
    [length(neighbors) < min_pts ? INF : sort([squared_distance(
        points[i],
        points[q]
    ) for q in neighbors])[min_pts] for (i,neighbors) in enumerate(neighborhoods)]
end
function optics_ordering(points,neighborhoods,core)
    n = length(points)
    reach,predecessor = fill(INF,n),zeros(Int,n)
    processed = falses(n)
    ordering = Int[]
    for start in 1:n
        processed[start] && continue
        seeds = Set([start])
        while !isempty(seeds)
            choices = collect(seeds)
            current = choices[argmin([(reach[i],points[i].id) for i in choices])]
            delete!(seeds,current)
            processed[current] = true
            push!(ordering,current)
            core[current] == INF && continue
            for other in neighborhoods[current]
                processed[other] && continue
                distance = max(core[current],squared_distance(points[current],points[other]))
                if distance < reach[other]
                    reach[other] = distance
                    predecessor[other] = current
                    push!(seeds,other)
                end
            end
        end
    end
    ordering,reach,predecessor
end
