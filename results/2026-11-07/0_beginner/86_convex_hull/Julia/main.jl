using Printf

cross_product(o, a, b) = (a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1])

function chain(points)
    result = Tuple{Int,Int}[]
    for point in points
        while length(result) >= 2 && cross_product(result[end-1], result[end], point) <= 0
            pop!(result)
        end
        push!(result, point)
    end
    return result
end

function main()
    points = sort([
        (3, 2),
        (-6, 1),
        (8, 4),
        (0, 0),
        (-3, 7),
        (4, -3),
        (1, -5),
        (-2, 1),
        (5, 6),
        (-6, -2),
        (2, -2),
        (7, -1),
        (-3, 4),
        (2, 8),
        (-6, 3),
    ])
    lower, upper = chain(points), chain(reverse(points))
    hull = vcat(lower[1:(end-1)], upper[1:(end-1)])
    println("hull: ", length(hull), " points")
    twice_area = 0
    for i in eachindex(hull)
        x, y = hull[i]
        next_x, next_y = hull[mod1(i+1, length(hull))]
        println("(", x, ", ", y, ")")
        twice_area += x*next_y-next_x*y
    end
    @printf("area: %.1f\n", twice_area/2)
end

main()
