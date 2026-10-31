function squared_distance(a,b)
    dx,dy = a[1]-b[1],a[2]-b[2]
    dx*dx+dy*dy
end
distance(a,b) = sqrt(squared_distance(a,b))
assignments(points,centers) = [argmin([squared_distance(
    point_xy(point),
    center
) for center in centers]) for point in points]
function run_kmeans(points,initial_centers,max_iterations)
    centers = copy(initial_centers)
    assigned = assignments(points,centers)
    iterations = 0
    for t in 1:max_iterations
        next_centers = Tuple{Float64,Float64}[]
        for k in eachindex(centers)
            members = [p for (p,label) in zip(points,assigned) if label==k]
            center = isempty(members) ? centers[k] : (
                ordered_sum(p.x for p in members)/length(members),
                ordered_sum(p.y for p in members)/length(members)
            )
            push!(next_centers,center)
        end
        centers = next_centers
        next_assignment = assignments(points,centers)
        iterations = t
        if next_assignment==assigned
            assigned = next_assignment
            break
        end
        assigned = next_assignment
    end
    inertia = ordered_sum(squared_distance(point_xy(p),centers[label]) for (p,label) in zip(points,assigned))
    (
        centers=centers,
        assignment=assigned,
        iterations=iterations,
        inertia=inertia,
        sizes=[count(==(k),assigned) for k in eachindex(centers)]
    )
end
