squared_distance(first, second) = ordered_sum((a - b) * (a - b) for (a, b) in zip(first, second))

function assign(points, centers)
    labels, errors = Int[], Float64[]
    for point in points
        distances = [squared_distance(point, center) for center in centers]
        distance, index = findmin(distances)
        push!(labels, index)
        push!(errors, distance)
    end
    labels, errors
end

function mean_point(points)
    totals = zeros(Float64, length(points[1]))
    for point in points, component in eachindex(totals)
        totals[component] += point[component]
    end
    totals ./ length(points)
end

cluster_sizes(labels, k) = [count(==(j), labels) for j in 1:k]
cluster_center(points, labels, j) = mean_point([point for (point, label) in zip(points, labels) if label == j])
cluster_centers(points, labels, k) = [cluster_center(points, labels, j) for j in 1:k]

function refill!(labels, errors, k)
    sizes = cluster_sizes(labels, k)
    reseeds = 0
    for j in 1:k
        sizes[j] > 0 && continue
        candidates = [i for (i, label) in enumerate(labels) if sizes[label] >= 2]
        chosen = candidates[findmax(errors[candidates])[2]]
        sizes[labels[chosen]] -= 1
        sizes[j] += 1
        labels[chosen] = j
        errors[chosen] = 0.0
        reseeds += 1
    end
    reseeds
end

struct LloydResult
    labels::Vector{Int}
    centers::Vector{Vector{Float64}}
    iterations::Int
    converged::Bool
    reseeds::Int
end

function lloyd(points, initial_centers, max_iterations)
    labels, errors = assign(points, initial_centers)
    iterations = reseeds = 0
    converged = false
    while iterations < max_iterations && !converged
        reseeds += refill!(labels, errors, length(initial_centers))
        centers = cluster_centers(points, labels, length(initial_centers))
        iterations += 1
        next, errors = assign(points, centers)
        converged = next == labels
        labels = next
    end
    reseeds += refill!(labels, errors, length(initial_centers))
    LloydResult(labels, cluster_centers(points, labels, length(initial_centers)), iterations, converged, reseeds)
end

sse(points, labels, centers) = ordered_sum(squared_distance(point, centers[label]) for (point, label) in zip(points, labels))
