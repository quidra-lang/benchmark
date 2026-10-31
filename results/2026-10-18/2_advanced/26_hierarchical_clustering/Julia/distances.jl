const DISTANCE_TYPES = (:euclidean, :manhattan, :correlation)

function sequential_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end

squared_distance(first, second) = sequential_sum((a - b) * (a - b) for (a, b) in zip(first, second))

function feature_statistics(rows)
    means = Float64[]
    deviations = Float64[]
    for f in eachindex(rows[1])
        mean = sequential_sum(row[f] for row in rows) / length(rows)
        variance = sequential_sum((row[f] - mean) * (row[f] - mean) for row in rows) / (length(rows) - 1)
        push!(means, mean)
        push!(deviations, sqrt(variance))
    end
    means, deviations
end

function standardize(rows, means, deviations)
    [[(row[f] - means[f]) / deviations[f] for f in eachindex(row)] for row in rows]
end

function distance(first, second, kind)
    if kind == :euclidean
        return sqrt(squared_distance(first, second))
    elseif kind == :manhattan
        return sequential_sum(abs(a - b) for (a, b) in zip(first, second))
    end
    mean_a = sequential_sum(first) / length(first)
    mean_b = sequential_sum(second) / length(second)
    cross = sequential_sum((a - mean_a) * (b - mean_b) for (a, b) in zip(first, second))
    spread_a = sequential_sum((a - mean_a) * (a - mean_a) for a in first)
    spread_b = sequential_sum((b - mean_b) * (b - mean_b) for b in second)
    1.0 - cross / sqrt(spread_a * spread_b)
end

function distance_matrix(vectors, kind)
    n = length(vectors)
    matrix = zeros(n, n)
    for i in 1:n, j in (i + 1):n
        value = distance(vectors[i], vectors[j], kind)
        matrix[i, j] = value
        matrix[j, i] = value
    end
    matrix
end
