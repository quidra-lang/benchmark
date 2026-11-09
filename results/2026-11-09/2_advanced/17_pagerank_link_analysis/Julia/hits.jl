function hits(n, nodes, links, iterations)
    sources, targets = [Int[] for _ in 1:n], [Int[] for _ in 1:n]
    for (source, target) in sort(links)
        push!(sources[target], source)
        push!(targets[source], target)
    end
    authority, hub = zeros(n), zeros(n)
    authority[nodes] .= 1
    hub[nodes] .= 1
    for _ in 1:iterations
        incoming, outgoing = zeros(n), zeros(n)
        for node in nodes, source in sources[node]
            incoming[node] += hub[source]
        end
        for node in nodes, target in targets[node]
            outgoing[node] += incoming[target]
        end
        norm_a = norm_h = 0.0
        for node in nodes
            norm_a += incoming[node] * incoming[node]
            norm_h += outgoing[node] * outgoing[node]
        end
        norm_a, norm_h = sqrt(norm_a), sqrt(norm_h)
        for node in nodes
            authority[node], hub[node] = incoming[node] / norm_a, outgoing[node] / norm_h
        end
    end
    authority, hub
end
