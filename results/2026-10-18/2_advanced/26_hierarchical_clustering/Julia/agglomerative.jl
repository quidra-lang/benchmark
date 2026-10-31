struct ClusteringMerge
    a::Int
    b::Int
    height::Float64
    size::Int
end

struct TreeEdge
    parent::Int
    child::Int
    weight::Float64
end

function lance_williams(method, size_a, size_b, size_k)
    a, b, k = Float64(size_a), Float64(size_b), Float64(size_k)
    if method == :single
        return (0.5, 0.5, 0.0, -0.5)
    elseif method == :complete
        return (0.5, 0.5, 0.0, 0.5)
    elseif method == :average
        return (a / (a + b), b / (a + b), 0.0, 0.0)
    elseif method == :weighted
        return (0.5, 0.5, 0.0, 0.0)
    elseif method == :centroid
        return (a / (a + b), b / (a + b), -(a * b) / ((a + b) * (a + b)), 0.0)
    elseif method == :median
        return (0.5, 0.5, -0.25, 0.0)
    end
    total = a + b + k
    ((a + k) / total, (b + k) / total, -k / total, 0.0)
end

function agglomerate(delta, method)
    n = size(delta, 1)
    squared = method in (:centroid, :median, :ward)
    capacity = 2 * n - 1
    values = zeros(capacity, capacity)
    for u in 1:n, w in 1:n
        values[u, w] = squared ? delta[u, w] * delta[u, w] : delta[u, w]
    end
    sizes = ones(Int, capacity)
    active = collect(1:n)
    merges = ClusteringMerge[]
    for step in 1:(n - 1)
        a, b = active[1], active[2]
        for position in eachindex(active), offset in (position + 1):length(active)
            u, w = active[position], active[offset]
            if values[u, w] < values[a, b]
                a, b = u, w
            end
        end
        node = n + step
        sizes[node] = sizes[a] + sizes[b]
        height = squared ? sqrt(values[a, b]) : values[a, b]
        push!(merges, ClusteringMerge(a, b, height, sizes[node]))
        for k in active
            (k == a || k == b) && continue
            alpha_a, alpha_b, beta, gamma = lance_williams(method, sizes[a], sizes[b], sizes[k])
            value = alpha_a * values[a, k] + alpha_b * values[b, k] + beta * values[a, b] + gamma * abs(values[a, k] - values[b, k])
            values[node, k] = value
            values[k, node] = value
        end
        filter!(u -> u != a && u != b, active)
        push!(active, node)
    end
    merges
end

function minimum_spanning_tree(delta)
    n = size(delta, 1)
    in_tree = falses(n)
    in_tree[1] = true
    keys = collect(delta[1, :])
    parents = ones(Int, n)
    edges = TreeEdge[]
    for _ in 1:(n - 1)
        chosen = 0
        for u in 1:n
            if !in_tree[u] && (chosen == 0 || keys[u] < keys[chosen])
                chosen = u
            end
        end
        in_tree[chosen] = true
        push!(edges, TreeEdge(parents[chosen], chosen, keys[chosen]))
        for u in 1:n
            if !in_tree[u] && delta[chosen, u] < keys[u]
                keys[u] = delta[chosen, u]
                parents[u] = chosen
            end
        end
    end
    edges
end
