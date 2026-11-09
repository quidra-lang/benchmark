function power_iteration(in_edges, teleport, damping, iterations, tolerance)
    n = length(in_edges)
    out_weight = zeros(Int, n)
    for edges in in_edges, (source, weight) in edges
        out_weight[source] += weight
    end
    dangling = findall(==(0), out_weight)
    in_teleport = falses(n)
    in_teleport[teleport] .= true
    size = length(teleport)
    values = [in_teleport[node] ? 1.0 / size : 0.0 for node in 1:n]
    changes, converged = Float64[], 0
    for step in 1:iterations
        dangling_mass = 0.0
        for node in dangling
            dangling_mass += values[node]
        end
        base = ((1 - damping) + damping * dangling_mass) / size
        updated = zeros(n)
        for node in 1:n
            inflow = 0.0
            for (source, weight) in in_edges[node]
                inflow += (values[source] * weight) / out_weight[source]
            end
            updated[node] = damping * inflow + (in_teleport[node] ? base : 0.0)
        end
        change = 0.0
        for node in 1:n
            change += abs(updated[node] - values[node])
        end
        push!(changes, change)
        converged == 0 && change < tolerance && (converged = step)
        values = updated
    end
    (; values, changes, converged)
end
