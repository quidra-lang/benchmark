function graph_neighbors(count,edges)
    upper,lower = [Int[] for _ in 1:count],[Int[] for _ in 1:count]
    for (a,b) in edges
        push!(lower[a],b)
        push!(upper[b],a)
    end
    upper,lower
end
function acyclic_order(node_count,edges)
    upper,lower = graph_neighbors(node_count,edges)
    remaining = Set(1:node_count)
    head,tail = Int[],Int[]
    while !isempty(remaining)
        candidates = sort(collect(remaining))
        indegree = [count(u -> u in remaining,upper[v]) for v in 1:node_count]
        outdegree = [count(w -> w in remaining,lower[v]) for v in 1:node_count]
        sinks = [v for v in candidates if outdegree[v] == 0]
        sources = [v for v in candidates if indegree[v] == 0]
        if !isempty(sinks)
            chosen = sinks[1]
            pushfirst!(tail,chosen)
        elseif !isempty(sources)
            chosen = sources[1]
            push!(head,chosen)
        else
            chosen = argmin(v -> (indegree[v]-outdegree[v],v),candidates)
            push!(head,chosen)
        end
        delete!(remaining,chosen)
    end
    [head;tail]
end
function assign_heights(node_count,edges,settings)
    upper,lower = graph_neighbors(node_count,edges)
    heights = fill(-1,node_count)
    labels = nothing
    if settings["layering"] == "coffman"
        labels = zeros(Int,node_count)
        for label in 1:node_count
            candidates = [v for v in 1:node_count if labels[v] == 0 && all(labels[u] > 0 for u in upper[v])]
            chosen = argmin(v -> (Tuple(sort(labels[upper[v]];rev=true)),v),candidates)
            labels[chosen] = label
        end
        current,occupied = 0,0
        for _ in 1:node_count
            candidates = [v for v in 1:node_count if heights[v] < 0 && all(heights[w] >= 0 for w in lower[v])]
            chosen = argmax(v -> labels[v],candidates)
            if occupied == settings["width"] || any(heights[w] == current for w in lower[chosen])
                current += 1
                occupied = 0
            end
            heights[chosen] = current
            occupied += 1
        end
    else
        for _ in 1:node_count
            chosen = findfirst(v -> heights[v] < 0 && all(heights[w] >= 0 for w in lower[v]),1:node_count)
            heights[chosen] = maximum((heights[w]+1 for w in lower[chosen]);init=0)
        end
    end
    dummies_before = sum((heights[a]-heights[b]-1 for (a,b) in edges);init=0)
    records = Tuple{Int,Int,Int}[]
    rounds = 0
    function promote(v)
        difference = 0
        for u in upper[v]
            heights[u] == heights[v]+1 && (difference += promote(u))
        end
        heights[v] += 1
        difference+length(lower[v])-length(upper[v])
    end
    if settings["promotion"] == "on"
        while true
            rounds += 1
            accepted = 0
            for v in 1:node_count
                isempty(upper[v]) && continue
                saved = copy(heights)
                difference = promote(v)
                if difference < 0
                    accepted += 1
                    push!(records,(rounds,v,difference))
                else
                    heights .= saved
                end
            end
            accepted == 0 && break
        end
    end
    heights,labels,dummies_before,rounds,records
end
