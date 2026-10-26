function distance_table(points)
    table = zeros(Float64, length(points), length(points))
    for i in eachindex(points), j in i+1:length(points)
        table[i, j] = table[j, i] = sqrt(squared_distance(points[i], points[j]))
    end
    table
end

function silhouettes(table, labels, sizes)
    result = Float64[]
    for i in eachindex(labels)
        own = labels[i]
        if sizes[own] == 1
            push!(result, 0.0)
            continue
        end
        totals = zeros(Float64, length(sizes))
        for j in eachindex(labels)
            j != i && (totals[labels[j]] += table[i, j])
        end
        inner = totals[own] / (sizes[own] - 1)
        outer = minimum(totals[j] / sizes[j] for j in eachindex(sizes) if j != own)
        largest = max(inner, outer)
        push!(result, largest == 0 ? 0.0 : (outer - inner) / largest)
    end
    result
end

function calinski_harabasz(points, centers, sizes, within)
    overall = mean_point(points)
    between = ordered_sum(size * squared_distance(center, overall) for (center, size) in zip(centers, sizes))
    (between / (length(centers) - 1)) / (within / (length(points) - length(centers)))
end

function davies_bouldin(points, labels, centers, sizes)
    spreads = zeros(Float64, length(centers))
    for (point, label) in zip(points, labels)
        spreads[label] += sqrt(squared_distance(point, centers[label]))
    end
    spreads ./= sizes
    worst = [maximum((spreads[a] + spreads[e]) / sqrt(squared_distance(centers[a], centers[e])) for e in eachindex(centers) if e != a) for a in eachindex(centers)]
    ordered_sum(worst) / length(centers)
end

function elbow(k, k_min, k_max, within, within_min, within_max)
    x = (k - k_min) / (k_max - k_min)
    y = (within - within_max) / (within_min - within_max)
    ((1 - x) - y) / sqrt(2)
end

hartigan(within, following, count, k) = (within / following - 1) * (count - k - 1)
pair_count(size) = div(size * (size - 1), 2)

function adjusted_rand_index(first::AbstractVector{T}, second::AbstractVector{U}) where {T,U}
    joint, a, b = Dict{Tuple{T,U},Int}(), Dict{T,Int}(), Dict{U,Int}()
    for (x, y) in zip(first, second)
        joint[(x, y)] = get(joint, (x, y), 0) + 1
        a[x] = get(a, x, 0) + 1
        b[y] = get(b, y, 0) + 1
    end
    total = pair_count(length(first))
    shared, first_pairs, second_pairs = [sum(pair_count, values(counts)) for counts in (joint, a, b)]
    numerator = 2 * (total * shared - first_pairs * second_pairs)
    denominator = total * (first_pairs + second_pairs) - 2 * first_pairs * second_pairs
    denominator == 0 ? 1.0 : numerator / denominator
end
