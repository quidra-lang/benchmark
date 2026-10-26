using Printf

function main()
    points = [
        (12, -7),
        (-33, 25),
        (41, 18),
        (-8, -44),
        (27, 39),
        (-46, -12),
        (5, 14),
        (36, -29),
        (-19, 47),
        (-2, 3),
    ]
    nearest, farthest = (0, 0, typemax(Int)), (0, 0, -1)
    for i = 1:(length(points)-1)
        for j = (i+1):length(points)
            dx = points[i][1]-points[j][1]
            dy = points[i][2]-points[j][2]
            squared = dx*dx+dy*dy
            if squared < nearest[3]
                nearest = (i-1, j-1, squared)
            end
            if squared > farthest[3]
                farthest = (i-1, j-1, squared)
            end
        end
    end
    for (label, pair) in [("closest", nearest), ("farthest", farthest)]
        distance = sqrt(Float64(pair[3]))
        @printf("%s: P%d P%d %.4f\n", label, pair[1], pair[2], distance)
    end
end

main()
