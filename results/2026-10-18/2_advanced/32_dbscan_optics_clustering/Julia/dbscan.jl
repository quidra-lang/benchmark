const NOISE = -1
function dbscan(neighborhoods,min_pts)
    core = length.(neighborhoods) .>= min_pts
    labels = fill(-2,length(neighborhoods))
    cluster = 0
    for p in eachindex(neighborhoods)
        labels[p] != -2 && continue
        if !core[p]
            labels[p] = NOISE
            continue
        end
        labels[p] = cluster
        queue = copy(neighborhoods[p])
        head = 1
        while head <= length(queue)
            q = queue[head]
            head += 1
            if labels[q] == NOISE
                labels[q] = cluster
            elseif labels[q] == -2
                labels[q] = cluster
                core[q] && append!(queue,neighborhoods[q])
            end
        end
        cluster += 1
    end
    labels,core
end
